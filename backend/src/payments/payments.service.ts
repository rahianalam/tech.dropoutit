import { BadRequestException, ConflictException, ForbiddenException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { Order, Prisma } from '@prisma/client';
import { randomBytes } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { meetingUrl } from '../bookings/slots';
import { PaymentGateway } from './gateway';

type Tx = Prisma.TransactionClient;
export const ORDER_TTL_MINUTES = 30;

const newTranId = () => `TD${Date.now().toString(36).toUpperCase()}${randomBytes(3).toString('hex').toUpperCase()}`;

/** Teacher's share after the gateway fee and platform commission (plan doc, algorithm C). */
export function teacherShare(paidPaisa: number, feePaisa: number, commissionBps: number): number {
  return Math.floor(((paidPaisa - feePaisa) * (10000 - commissionBps)) / 10000);
}

@Injectable()
export class PaymentsService {
  private log = new Logger('Payments');
  constructor(
    private prisma: PrismaService,
    private gateway: PaymentGateway,
  ) {}

  /**
   * Starts checkout for a paid course. Reuses a still-fresh pending order so a
   * double tap does not create two orders.
   */
  async checkoutCourse(userId: string, courseId: string) {
    const course = await this.prisma.course.findUnique({ where: { id: courseId } });
    if (!course || course.status !== 'PUBLISHED') throw new NotFoundException('Course not found');
    if (course.isFree) throw new BadRequestException('This course is free; enroll directly');
    if (course.teacherId === userId) throw new ForbiddenException('You cannot buy your own course');
    const enrolled = await this.prisma.enrollment.findUnique({ where: { userId_courseId: { userId, courseId } } });
    if (enrolled?.status === 'ACTIVE') throw new ConflictException('You are already enrolled');

    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    const fresh = new Date(Date.now() - (ORDER_TTL_MINUTES - 5) * 60_000);
    const order =
      (await this.prisma.order.findFirst({
        where: { userId, itemType: 'COURSE', itemId: courseId, status: 'PENDING', amountPaisa: course.pricePaisa, createdAt: { gte: fresh } },
      })) ??
      (await this.prisma.order.create({
        data: {
          userId,
          itemType: 'COURSE',
          itemId: courseId,
          amountPaisa: course.pricePaisa,
          tranId: newTranId(),
        },
      }));

    const gatewayUrl = await this.gateway.createCheckout({
      tranId: order.tranId,
      amountPaisa: order.amountPaisa,
      productName: course.title,
      productCategory: 'Online course',
      customer: { name: user.name, email: user.email, phone: user.phone },
    });
    return { orderId: order.id, tranId: order.tranId, amountPaisa: order.amountPaisa, gatewayUrl };
  }

  /** Starts checkout for a held session booking (created by BookingsService.book). */
  async checkoutBooking(userId: string, bookingId: string) {
    const booking = await this.prisma.booking.findUniqueOrThrow({ where: { id: bookingId }, include: { teacher: true } });
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    const order = await this.prisma.order.create({
      data: { userId, itemType: 'BOOKING', itemId: bookingId, amountPaisa: booking.pricePaisa, tranId: newTranId() },
    });
    await this.prisma.booking.update({ where: { id: bookingId }, data: { orderId: order.id } });
    const gatewayUrl = await this.gateway.createCheckout({
      tranId: order.tranId,
      amountPaisa: order.amountPaisa,
      productName: `1:1 session with ${booking.teacher.name}`,
      productCategory: 'Online session',
      customer: { name: user.name, email: user.email, phone: user.phone },
    });
    return { orderId: order.id, tranId: order.tranId, amountPaisa: order.amountPaisa, gatewayUrl };
  }

  /**
   * Called from the gateway's IPN and success callbacks. Verifies with the
   * gateway, then fulfils exactly once (plan doc, algorithm B).
   */
  async handleCallback(valId: string | undefined, tranId?: string): Promise<{ order: Order | null; ok: boolean }> {
    if (!valId) return { order: tranId ? await this.prisma.order.findUnique({ where: { tranId } }) : null, ok: false };
    const v = await this.gateway.verify(valId);
    const order = await this.prisma.order.findUnique({ where: { tranId: v.tranId ?? tranId ?? '' } });
    if (!order) {
      this.log.warn(`callback for unknown tran_id ${v.tranId}`);
      return { order: null, ok: false };
    }
    if (!v.valid) return { order, ok: false };
    if (v.amountPaisa !== order.amountPaisa) {
      this.log.error(`amount mismatch on ${order.tranId}: paid ${v.amountPaisa}, expected ${order.amountPaisa}`);
      return { order, ok: false };
    }
    const fulfilled = await this.fulfil(order.id, { gatewayRef: v.gatewayRef, feePaisa: v.feePaisa, amountPaisa: v.amountPaisa, raw: v.raw });
    return { order: fulfilled, ok: fulfilled.status === 'PAID' };
  }

  /** Idempotent: a second call for the same order changes nothing. */
  async fulfil(orderId: string, payment: { gatewayRef: string; feePaisa: number; amountPaisa: number; raw: unknown }) {
    return this.prisma.$transaction(async (tx) => {
      // Flip PENDING (or a late payment on an EXPIRED order) to PAID; only one caller wins.
      const won = await tx.order.updateMany({
        where: { id: orderId, status: { in: ['PENDING', 'EXPIRED', 'FAILED'] } },
        data: { status: 'PAID', paidAt: new Date() },
      });
      const order = await tx.order.findUniqueOrThrow({ where: { id: orderId } });
      if (won.count === 0) return order;

      await tx.payment.create({
        data: {
          orderId,
          gateway: this.gateway.name,
          gatewayRef: payment.gatewayRef,
          amountPaisa: payment.amountPaisa,
          feePaisa: payment.feePaisa,
          rawPayload: payment.raw as Prisma.InputJsonValue,
          verifiedAt: new Date(),
        },
      });

      if (order.itemType === 'COURSE') {
        const course = await tx.course.findUniqueOrThrow({ where: { id: order.itemId } });
        await tx.enrollment.upsert({
          where: { userId_courseId: { userId: order.userId, courseId: course.id } },
          create: { userId: order.userId, courseId: course.id, orderId },
          update: { status: 'ACTIVE', orderId },
        });
        await this.recordEarning(tx, order, course.teacherId, payment.feePaisa, 'course');
        await tx.notification.create({ data: { userId: order.userId, title: 'পেমেন্ট সফল', body: `"${course.title}" কোর্সে আপনি এনরোলড।` } });
      }

      if (order.itemType === 'BOOKING') {
        await this.confirmBooking(tx, order, payment.feePaisa);
      }
      return order;
    });
  }

  /**
   * Paid booking → CONFIRMED with a meeting link. If the hold had expired and
   * someone else took the slot meanwhile, the student is told a refund is coming.
   */
  private async confirmBooking(tx: Tx, order: Order, feePaisa: number) {
    const b = await tx.booking.findUnique({ where: { id: order.itemId }, include: { teacher: true, student: true } });
    if (!b) return;
    const clash = await tx.booking.findFirst({ where: { teacherId: b.teacherId, startAt: b.startAt, slotLock: 'live', id: { not: b.id } } });
    if (clash || !['HELD', 'CANCELLED'].includes(b.status) || (b.status === 'CANCELLED' && b.cancelledBy !== 'system')) {
      await tx.notification.create({ data: { userId: b.studentId, title: 'স্লটটি আর খালি নেই', body: 'পেমেন্ট দেরিতে পৌঁছেছে এবং স্লটটি অন্য কেউ নিয়েছে। পূর্ণ টাকা ফেরত দেওয়া হবে।' } });
      const admins = await tx.userRole.findMany({ where: { role: 'ADMIN' } });
      await tx.notification.createMany({ data: admins.map((a) => ({ userId: a.userId, title: 'রিফান্ড দরকার', body: `অর্ডার ${order.tranId}: স্লট হারানো বুকিং` })) });
      return;
    }
    await tx.booking.update({ where: { id: b.id }, data: { status: 'CONFIRMED', slotLock: 'live', meetingUrl: b.meetingUrl ?? meetingUrl(), cancelledBy: null } });
    await this.recordEarning(tx, order, b.teacherId, feePaisa, 'session');
    const when = b.startAt.toLocaleString('en-GB', { timeZone: 'Asia/Dhaka', dateStyle: 'medium', timeStyle: 'short' });
    await tx.notification.createMany({
      data: [
        { userId: b.studentId, title: 'সেশন নিশ্চিত', body: `${b.teacher.name}-এর সাথে ${when}` },
        { userId: b.teacherId, title: 'নতুন সেশন বুকিং', body: `${b.student.name} · ${when}` },
      ],
    });
  }

  /** Credits the teacher's ledger. The admin's own (official) courses earn nothing to pay out. */
  async recordEarning(tx: Tx, order: Order, teacherId: string, feePaisa: number, kind: 'course' | 'session') {
    const isAdmin = await tx.userRole.findUnique({ where: { userId_role: { userId: teacherId, role: 'ADMIN' } } });
    if (isAdmin) return;
    const settings = await tx.platformSettings.upsert({ where: { id: 1 }, create: { id: 1 }, update: {} });
    const profile = await tx.teacherProfile.findUnique({ where: { userId: teacherId } });
    const commissionBps =
      kind === 'course'
        ? (profile?.courseCommissionBps ?? settings.courseCommissionBps)
        : (profile?.sessionCommissionBps ?? settings.sessionCommissionBps);
    await tx.ledgerEntry.create({
      data: {
        teacherId,
        orderId: order.id,
        type: 'EARNING',
        amountPaisa: teacherShare(order.amountPaisa, feePaisa, commissionBps),
        commissionBps,
        status: 'PENDING',
        availableAt: new Date(Date.now() + settings.holdDays * 864e5),
      },
    });
  }

  async markFailed(tranId: string) {
    await this.prisma.order.updateMany({ where: { tranId, status: 'PENDING' }, data: { status: 'FAILED' } });
  }

  async getOrder(id: string, userId: string) {
    const order = await this.prisma.order.findUnique({ where: { id } });
    if (!order || order.userId !== userId) throw new NotFoundException();
    return order;
  }

  myOrders(userId: string) {
    return this.prisma.order.findMany({ where: { userId }, orderBy: { createdAt: 'desc' }, take: 50 });
  }

  /**
   * Admin refund. The money itself is returned from the SSLCommerz merchant
   * panel; this records it: access removed, teacher earning voided, or clawed
   * back from the next payout if it was already paid.
   */
  async refund(orderId: string, adminId: string) {
    return this.prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      if (!order) throw new NotFoundException();
      if (order.status !== 'PAID') throw new ConflictException(`Order is ${order.status}`);
      await tx.order.update({ where: { id: orderId }, data: { status: 'REFUNDED', refundedAt: new Date() } });
      await tx.enrollment.updateMany({ where: { orderId }, data: { status: 'REFUNDED' } });
      await tx.booking.updateMany({ where: { orderId }, data: { status: 'CANCELLED' } });
      const earnings = await tx.ledgerEntry.findMany({ where: { orderId, type: 'EARNING' } });
      for (const e of earnings) {
        if (e.status === 'PAID') {
          await tx.ledgerEntry.create({
            data: { teacherId: e.teacherId, orderId, type: 'REFUND', amountPaisa: -e.amountPaisa, status: 'AVAILABLE', availableAt: new Date() },
          });
        } else {
          await tx.ledgerEntry.update({ where: { id: e.id }, data: { status: 'VOID', payoutId: null } });
        }
      }
      await tx.auditLog.create({ data: { actorId: adminId, action: 'order.refund', target: orderId } });
      return tx.order.findUniqueOrThrow({ where: { id: orderId } });
    });
  }

  /** Pending orders older than the TTL become EXPIRED (a late valid IPN still fulfils them). */
  expireStale() {
    return this.prisma.order.updateMany({
      where: { status: 'PENDING', createdAt: { lt: new Date(Date.now() - ORDER_TTL_MINUTES * 60_000) } },
      data: { status: 'EXPIRED' },
    });
  }
}
