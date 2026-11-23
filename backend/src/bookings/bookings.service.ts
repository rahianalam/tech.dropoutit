import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AuthUser } from '../common/auth.decorators';
import { settingsOf } from '../fees/fees';
import { PaymentsService, respondBy } from '../payments/payments.service';
import { PrismaService } from '../prisma/prisma.service';
import { generateSlots, HOLD_MINUTES, meetingUrl, overlaps, Rule } from './slots';

const LIVE = ['HELD', 'REQUESTED', 'CONFIRMED', 'COMPLETED'] as const;
const STUDENT_CANCEL_HOURS = 24;
const person = { select: { id: true, name: true, avatarUrl: true } } as const;

@Injectable()
export class BookingsService {
  constructor(
    private prisma: PrismaService,
    private payments: PaymentsService,
  ) {}

  // ---------- availability ----------

  rules(teacherId: string) {
    return this.prisma.availabilityRule.findMany({ where: { teacherId }, orderBy: [{ weekday: 'asc' }, { startMinute: 'asc' }] });
  }

  /** Replaces the teacher's weekly schedule. Overlapping windows on the same day are rejected. */
  async setRules(teacherId: string, rules: Omit<Rule, 'timezone'>[]) {
    for (const [i, r] of rules.entries()) {
      if (r.endMinute - r.startMinute < r.slotMinutes) throw new BadRequestException(`Rule ${i + 1}: window shorter than one slot`);
      if (rules.some((o, j) => j !== i && overlaps(r, o))) throw new BadRequestException(`Rule ${i + 1} overlaps another rule`);
    }
    await this.prisma.$transaction([
      this.prisma.availabilityRule.deleteMany({ where: { teacherId } }),
      this.prisma.availabilityRule.createMany({ data: rules.map((r) => ({ ...r, teacherId, timezone: 'Asia/Dhaka' })) }),
    ]);
    return this.rules(teacherId);
  }

  /**
   * Price follows the length of the session: a paid slot costs the instructor's
   * hourly rate x minutes / 60. A slot saved as free (0) stays a free intro.
   */
  async pricedRules(teacherId: string) {
    const [rules, profile] = await Promise.all([this.rules(teacherId), this.prisma.teacherProfile.findUnique({ where: { userId: teacherId } })]);
    const rate = profile?.hourlyRatePaisa;
    return rules.map((r) => ({ ...r, pricePaisa: r.pricePaisa === 0 || !rate ? r.pricePaisa : Math.round((rate * r.slotMinutes) / 60 / 100) * 100 }));
  }

  /** Expired holds stop blocking their slot. */
  releaseExpiredHolds() {
    return this.prisma.booking.updateMany({
      where: { status: 'HELD', heldUntil: { lt: new Date() } },
      data: { status: 'CANCELLED', slotLock: null, cancelledBy: 'system' },
    });
  }

  async slots(teacherId: string, days = 14) {
    const isTeacher = await this.prisma.userRole.findUnique({ where: { userId_role: { userId: teacherId, role: 'TEACHER' } } });
    if (!isTeacher) throw new NotFoundException('Teacher not found');
    await this.releaseExpiredHolds();
    const now = new Date();
    const until = new Date(now.getTime() + (days + 1) * 864e5);
    const [rules, booked] = await Promise.all([
      this.pricedRules(teacherId),
      this.prisma.booking.findMany({ where: { teacherId, slotLock: 'live', startAt: { gte: now, lte: until } }, select: { startAt: true } }),
    ]);
    return generateSlots(rules, booked.map((b) => b.startAt), now, Math.min(days, 30), now);
  }

  // ---------- booking ----------

  /**
   * Holds the slot for HOLD_MINUTES and starts checkout. The unique
   * (teacher, startAt, slotLock) key means two students racing for the same
   * slot can't both get it.
   */
  async book(student: AuthUser, teacherId: string, startAt: Date) {
    if (teacherId === student.id) throw new ForbiddenException('You cannot book yourself');
    const slot = (await this.slots(teacherId, 30)).find((s) => s.startAt.getTime() === startAt.getTime());
    if (!slot) throw new ConflictException('This slot is no longer available');

    let booking;
    try {
      booking = await this.prisma.booking.create({
        data: {
          teacherId,
          studentId: student.id,
          startAt: slot.startAt,
          endAt: slot.endAt,
          pricePaisa: slot.pricePaisa,
          // A free session goes straight to the instructor as a request; a paid one is
          // held while the student pays, then becomes a request.
          status: slot.pricePaisa === 0 ? 'REQUESTED' : 'HELD',
          heldUntil: new Date(Date.now() + HOLD_MINUTES * 60_000),
          respondBy: slot.pricePaisa === 0 ? respondBy(slot.startAt, (await settingsOf(this.prisma)).bookingResponseHours) : null,
        },
      });
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') throw new ConflictException('Someone just booked this slot');
      throw e;
    }
    if (slot.pricePaisa === 0) {
      await this.notifyRequested(booking.id);
      return { booking, gatewayUrl: null, orderId: null };
    }
    const checkout = await this.payments.checkoutBooking(student.id, booking.id);
    return { booking, ...checkout };
  }

  async notifyRequested(bookingId: string) {
    const b = await this.prisma.booking.findUniqueOrThrow({ where: { id: bookingId }, include: { student: true, teacher: true } });
    const when = b.startAt.toLocaleString('en-GB', { timeZone: 'Asia/Dhaka', dateStyle: 'medium', timeStyle: 'short' });
    await this.prisma.notification.createMany({
      data: [
        { userId: b.studentId, title: 'বুকিং রিকোয়েস্ট পাঠানো হয়েছে', body: `${b.teacher.name} গ্রহণ করলে সেশন নিশ্চিত হবে (${when})।` },
        { userId: b.teacherId, title: 'নতুন বুকিং রিকোয়েস্ট', body: `${b.student.name} · ${when}। গ্রহণ বা বাতিল করুন।` },
      ],
    });
  }

  /** Instructor accepts a request: the session is confirmed and the paid amount goes into escrow for them. */
  async accept(id: string, user: AuthUser) {
    const b = await this.load(id);
    if (b.teacherId !== user.id) throw new ForbiddenException();
    if (b.status !== 'REQUESTED') throw new ConflictException(`Booking is ${b.status}`);
    const updated = await this.prisma.$transaction(async (tx) => {
      const res = await tx.booking.updateMany({ where: { id, status: 'REQUESTED' }, data: { status: 'CONFIRMED', meetingUrl: b.meetingUrl ?? meetingUrl(), respondBy: null } });
      if (!res.count) throw new ConflictException('This request was already answered');
      if (b.order?.status === 'PAID') await this.payments.recordEarning(tx, b.order, b.teacherId, 0, 'session', b.endAt);
      return tx.booking.findUniqueOrThrow({ where: { id } });
    });
    await this.notifyConfirmed(id);
    return updated;
  }

  /** Instructor declines (or the request ran out of time): the slot opens again and a paid booking is refunded. */
  async decline(id: string, user: AuthUser | null, note?: string) {
    const b = await this.load(id);
    if (user && b.teacherId !== user.id && !user.roles.includes('ADMIN')) throw new ForbiddenException();
    if (b.status !== 'REQUESTED') throw new ConflictException(`Booking is ${b.status}`);
    const res = await this.prisma.booking.updateMany({
      where: { id, status: 'REQUESTED' },
      data: { status: 'CANCELLED', slotLock: null, cancelledBy: user ? 'teacher' : 'system', declineNote: note, respondBy: null },
    });
    if (!res.count) throw new ConflictException('This request was already answered');
    const paid = b.order?.status === 'PAID';
    if (paid) await this.payments.refund(b.order!.id, user?.id ?? b.teacherId);
    const why = user ? 'ইন্সট্রাক্টর রিকোয়েস্টটি গ্রহণ করতে পারেননি' : 'ইন্সট্রাক্টর সময়মতো উত্তর দেননি';
    await this.prisma.notification.create({
      data: { userId: b.studentId, title: 'বুকিং গ্রহণ হয়নি', body: `${why}${note ? `: ${note}` : ''}।${paid ? ' পুরো টাকা ফেরত দেওয়া হবে।' : ''}` },
    });
    if (paid) await this.notifyAdmins('রিফান্ড দরকার', `গ্রহণ না হওয়া বুকিংয়ের অর্ডার ${b.order!.tranId}: SSLCommerz প্যানেল থেকে টাকা ফেরত দিন।`);
    return this.prisma.booking.findUniqueOrThrow({ where: { id } });
  }

  /** Requests the instructor did not answer in time are declined and refunded. */
  async expireRequests(now = new Date()) {
    const late = await this.prisma.booking.findMany({ where: { status: 'REQUESTED', respondBy: { lt: now } }, select: { id: true } });
    for (const { id } of late) await this.decline(id, null).catch(() => undefined);
    return late.length;
  }

  async notifyConfirmed(bookingId: string) {
    const b = await this.prisma.booking.findUniqueOrThrow({ where: { id: bookingId }, include: { student: true, teacher: true } });
    const when = b.startAt.toLocaleString('en-GB', { timeZone: 'Asia/Dhaka', dateStyle: 'medium', timeStyle: 'short' });
    await this.prisma.notification.createMany({
      data: [
        { userId: b.studentId, title: 'সেশন নিশ্চিত', body: `${b.teacher.name}-এর সাথে ${when}` },
        { userId: b.teacherId, title: 'নতুন সেশন বুকিং', body: `${b.student.name} · ${when}` },
      ],
    });
  }

  mine(userId: string) {
    return this.prisma.booking.findMany({
      where: { studentId: userId, status: { not: 'HELD' } },
      orderBy: { startAt: 'desc' },
      include: { teacher: person, review: true },
    });
  }

  forTeacher(teacherId: string) {
    return this.prisma.booking.findMany({
      where: { teacherId, status: { in: ['REQUESTED', 'CONFIRMED', 'COMPLETED', 'NO_SHOW', 'CANCELLED'] }, OR: [{ orderId: null }, { order: { status: { not: 'PENDING' } } }] },
      orderBy: { startAt: 'desc' },
      take: 100,
      include: { student: person },
    });
  }

  private async load(id: string) {
    const b = await this.prisma.booking.findUnique({ where: { id }, include: { order: true } });
    if (!b) throw new NotFoundException('Booking not found');
    return b;
  }

  /**
   * Cancellation rules (plan doc, algorithm E):
   * the teacher can cancel any confirmed session; the student up to 24 hours before.
   * A paid booking is refunded in full (money returned from the SSLCommerz panel).
   */
  async cancel(id: string, user: AuthUser) {
    const b = await this.load(id);
    const isTeacher = b.teacherId === user.id;
    const isStudent = b.studentId === user.id;
    if (!isTeacher && !isStudent && !user.roles.includes('ADMIN')) throw new ForbiddenException();
    if (b.status === 'REQUESTED' && isTeacher) return this.decline(id, user);
    if (b.status !== 'CONFIRMED' && b.status !== 'REQUESTED') throw new ConflictException(`Booking is ${b.status}`);
    if (b.status === 'CONFIRMED' && isStudent && !isTeacher && b.startAt.getTime() - Date.now() < STUDENT_CANCEL_HOURS * 3600_000) {
      throw new BadRequestException('Sessions can be cancelled up to 24 hours before the start');
    }
    if (b.order?.status === 'PAID') {
      await this.payments.refund(b.order.id, user.id);
    }
    const updated = await this.prisma.booking.update({
      where: { id },
      data: { status: 'CANCELLED', slotLock: null, cancelledBy: isTeacher ? 'teacher' : isStudent ? 'student' : 'admin' },
    });
    const other = isTeacher ? b.studentId : b.teacherId;
    await this.prisma.notification.create({
      data: { userId: other, title: 'সেশন বাতিল', body: b.order?.status === 'PAID' ? 'সেশনটি বাতিল হয়েছে। পূর্ণ টাকা ফেরত দেওয়া হবে।' : 'সেশনটি বাতিল হয়েছে।' },
    });
    if (b.order?.status === 'PAID') await this.notifyAdmins('রিফান্ড দরকার', `বাতিল সেশনের অর্ডার ${b.order.tranId}: SSLCommerz প্যানেল থেকে টাকা ফেরত দিন।`);
    return updated;
  }

  /** After the start time the teacher marks the session done, or the student absent. */
  async complete(id: string, user: AuthUser, outcome: 'COMPLETED' | 'NO_SHOW') {
    const b = await this.load(id);
    if (b.teacherId !== user.id && !user.roles.includes('ADMIN')) throw new ForbiddenException();
    if (b.status !== 'CONFIRMED') throw new ConflictException(`Booking is ${b.status}`);
    if (b.startAt > new Date()) throw new BadRequestException('The session has not started yet');
    return this.prisma.booking.update({ where: { id }, data: { status: outcome, slotLock: outcome === 'NO_SHOW' ? null : 'live' } });
  }

  /** Student says the teacher didn't show up: the admin decides, and can refund from the orders screen. */
  async report(id: string, user: AuthUser, reason: string) {
    const b = await this.load(id);
    if (b.studentId !== user.id) throw new ForbiddenException();
    if (b.startAt > new Date()) throw new BadRequestException('The session has not started yet');
    await this.notifyAdmins('সেশন নিয়ে অভিযোগ', `বুকিং ${id}${b.order ? ` (অর্ডার ${b.order.tranId})` : ''}: ${reason}`);
    await this.prisma.auditLog.create({ data: { actorId: user.id, action: 'booking.report', target: id, meta: { reason } } });
    return { reported: true };
  }

  async notifyAdmins(title: string, body: string) {
    const admins = await this.prisma.userRole.findMany({ where: { role: 'ADMIN' } });
    await this.prisma.notification.createMany({ data: admins.map((a) => ({ userId: a.userId, title, body })) });
  }

  /** Confirmed sessions that ended a day ago with no report count as completed. */
  autoComplete() {
    return this.prisma.booking.updateMany({
      where: { status: 'CONFIRMED', endAt: { lt: new Date(Date.now() - 864e5) } },
      data: { status: 'COMPLETED' },
    });
  }

  /** In-app reminders 24 hours and 15 minutes before (push notifications come with FCM in phase 5). */
  async sendReminders(now = new Date()) {
    const due = async (field: 'reminded24' | 'reminded15', minutes: number, text: string) => {
      const list = await this.prisma.booking.findMany({
        where: { status: 'CONFIRMED', [field]: false, startAt: { gt: now, lte: new Date(now.getTime() + minutes * 60_000) } },
        include: { teacher: true, student: true },
      });
      for (const b of list) {
        await this.prisma.$transaction([
          this.prisma.notification.createMany({
            data: [
              { userId: b.studentId, title: 'সেশন রিমাইন্ডার', body: `${b.teacher.name}-এর সাথে সেশন ${text}` },
              { userId: b.teacherId, title: 'সেশন রিমাইন্ডার', body: `${b.student.name}-এর সাথে সেশন ${text}` },
            ],
          }),
          this.prisma.booking.update({ where: { id: b.id }, data: { [field]: true } }),
        ]);
      }
      return list.length;
    };
    return { day: await due('reminded24', 24 * 60, 'আগামীকাল এই সময়ে'), soon: await due('reminded15', 15, '১৫ মিনিট পরে শুরু') };
  }

  // ---------- reviews ----------

  async reviewBooking(id: string, user: AuthUser, rating: number, comment?: string) {
    const b = await this.load(id);
    if (b.studentId !== user.id) throw new ForbiddenException();
    if (b.status !== 'COMPLETED') throw new BadRequestException('You can review after the session is completed');
    return this.prisma.review.upsert({
      where: { bookingId: id },
      create: { userId: user.id, bookingId: id, rating, comment },
      update: { rating, comment },
    });
  }
}
