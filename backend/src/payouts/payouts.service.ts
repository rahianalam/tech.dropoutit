import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PayoutSchedule } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

/** Day of month and weekday in Bangladesh time (UTC+6, no DST). */
export function dhakaDate(d: Date) {
  const local = new Date(d.getTime() + 6 * 3600_000);
  return { day: local.getUTCDate(), weekday: local.getUTCDay() };
}

/** MONTHLY pays on the admin's chosen day; WEEKLY pays on Sunday (the Bangladeshi work week starts Sunday); MANUAL never auto-runs. */
export function isPayoutDay(schedule: PayoutSchedule, dayOfMonth: number, now = new Date()): boolean {
  const { day, weekday } = dhakaDate(now);
  if (schedule === 'MONTHLY') return day === dayOfMonth;
  if (schedule === 'WEEKLY') return weekday === 0;
  return false;
}

@Injectable()
export class PayoutsService {
  constructor(private prisma: PrismaService) {}

  /** Earnings whose hold period has passed become withdrawable. */
  releaseMatured(now = new Date()) {
    return this.prisma.ledgerEntry.updateMany({
      where: { status: 'PENDING', type: 'EARNING', availableAt: { lte: now } },
      data: { status: 'AVAILABLE' },
    });
  }

  /**
   * Drafts one payout per teacher whose unpaid AVAILABLE balance (earnings minus
   * refund claw-backs) reaches the minimum. The admin then approves and pays.
   */
  async generateDrafts() {
    await this.releaseMatured();
    const settings = await this.prisma.platformSettings.upsert({ where: { id: 1 }, create: { id: 1 }, update: {} });
    const balances = await this.prisma.ledgerEntry.groupBy({
      by: ['teacherId'],
      where: { status: 'AVAILABLE', payoutId: null },
      _sum: { amountPaisa: true },
    });
    const created = [];
    for (const b of balances) {
      const amount = b._sum.amountPaisa ?? 0;
      if (amount <= 0 || amount < settings.minPayoutPaisa) continue;
      const profile = await this.prisma.teacherProfile.findUnique({ where: { userId: b.teacherId } });
      const payout = await this.prisma.$transaction(async (tx) => {
        const p = await tx.payout.create({
          data: { teacherId: b.teacherId, amountPaisa: amount, method: profile?.payoutMethod, account: profile?.payoutAccount },
        });
        await tx.ledgerEntry.updateMany({ where: { teacherId: b.teacherId, status: 'AVAILABLE', payoutId: null }, data: { payoutId: p.id } });
        return p;
      });
      created.push(payout);
    }
    return created;
  }

  list(status?: 'DRAFT' | 'APPROVED' | 'PAID') {
    return this.prisma.payout.findMany({
      where: status ? { status } : {},
      orderBy: { createdAt: 'desc' },
      include: { teacher: { select: { id: true, name: true, phone: true, email: true } } },
    });
  }

  async approve(id: string, adminId: string) {
    const p = await this.prisma.payout.findUnique({ where: { id } });
    if (!p) throw new NotFoundException();
    if (p.status !== 'DRAFT') throw new ConflictException(`Payout is ${p.status}`);
    await this.prisma.auditLog.create({ data: { actorId: adminId, action: 'payout.approve', target: id } });
    return this.prisma.payout.update({ where: { id }, data: { status: 'APPROVED' } });
  }

  /** Records that the money was sent (bKash/Nagad/bank) with its transaction reference. */
  async markPaid(id: string, adminId: string, reference: string) {
    return this.prisma.$transaction(async (tx) => {
      const p = await tx.payout.findUnique({ where: { id } });
      if (!p) throw new NotFoundException();
      if (p.status !== 'APPROVED') throw new ConflictException('Approve the payout first');
      await tx.ledgerEntry.updateMany({ where: { payoutId: id }, data: { status: 'PAID' } });
      await tx.notification.create({
        data: { userId: p.teacherId, title: 'পেআউট পাঠানো হয়েছে', body: `৳${p.amountPaisa / 100} পাঠানো হয়েছে। রেফারেন্স: ${reference}` },
      });
      await tx.auditLog.create({ data: { actorId: adminId, action: 'payout.paid', target: id, meta: { reference } } });
      return tx.payout.update({ where: { id }, data: { status: 'PAID', reference, paidAt: new Date() } });
    });
  }

  /** Drops a draft or approved payout; its entries go back to the available balance. */
  async cancel(id: string) {
    return this.prisma.$transaction(async (tx) => {
      const p = await tx.payout.findUnique({ where: { id } });
      if (!p) throw new NotFoundException();
      if (p.status === 'PAID') throw new ConflictException('A paid payout cannot be cancelled');
      await tx.ledgerEntry.updateMany({ where: { payoutId: id }, data: { payoutId: null } });
      await tx.payout.delete({ where: { id } });
    });
  }

  async earnings(teacherId: string) {
    await this.releaseMatured();
    const sum = async (where: object) =>
      (await this.prisma.ledgerEntry.aggregate({ where: { teacherId, ...where }, _sum: { amountPaisa: true } }))._sum.amountPaisa ?? 0;
    const [pendingPaisa, availablePaisa, paidPaisa, entries, payouts, profile, settings] = await Promise.all([
      sum({ status: 'PENDING' }),
      sum({ status: 'AVAILABLE' }),
      sum({ status: 'PAID', type: 'EARNING' }),
      this.prisma.ledgerEntry.findMany({ where: { teacherId, status: { not: 'VOID' } }, orderBy: { createdAt: 'desc' }, take: 50 }),
      this.prisma.payout.findMany({ where: { teacherId }, orderBy: { createdAt: 'desc' }, take: 20 }),
      this.prisma.teacherProfile.findUnique({ where: { userId: teacherId }, select: { payoutMethod: true, payoutAccount: true } }),
      this.prisma.platformSettings.upsert({ where: { id: 1 }, create: { id: 1 }, update: {} }),
    ]);
    return {
      pendingPaisa,
      availablePaisa,
      paidPaisa,
      payoutAccount: profile,
      schedule: { payoutSchedule: settings.payoutSchedule, payoutDayOfMonth: settings.payoutDayOfMonth, minPayoutPaisa: settings.minPayoutPaisa, holdDays: settings.holdDays },
      entries,
      payouts,
    };
  }

  async revenue() {
    const paid = await this.prisma.order.aggregate({ where: { status: 'PAID' }, _sum: { amountPaisa: true }, _count: true });
    const fees = await this.prisma.payment.aggregate({ where: { order: { status: 'PAID' } }, _sum: { feePaisa: true } });
    const teacherOwed = await this.prisma.ledgerEntry.aggregate({ where: { status: { in: ['PENDING', 'AVAILABLE'] } }, _sum: { amountPaisa: true } });
    const teacherPaid = await this.prisma.ledgerEntry.aggregate({ where: { status: 'PAID' }, _sum: { amountPaisa: true } });
    const gross = paid._sum.amountPaisa ?? 0;
    const fee = fees._sum.feePaisa ?? 0;
    const owed = teacherOwed._sum.amountPaisa ?? 0;
    const sent = teacherPaid._sum.amountPaisa ?? 0;
    return { paidOrders: paid._count, grossPaisa: gross, gatewayFeesPaisa: fee, teacherOwedPaisa: owed, teacherPaidPaisa: sent, platformNetPaisa: gross - fee - owed - sent };
  }
}
