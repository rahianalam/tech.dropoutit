import { PlatformSettings, Prisma } from '@prisma/client';

type Db = Prisma.TransactionClient;

export type Tier = 'GOLD' | 'SILVER' | null;

/**
 * Fiverr/Upwork style: the student pays the listed price, the platform keeps its
 * commission and the VAT, and the instructor gets the rest. The payment gateway's
 * own fee is paid by the platform, so the instructor sees exactly
 * price - commission - VAT.
 */
export function feeBreakdown(grossPaisa: number, commissionBps: number, vatBps: number) {
  const commissionPaisa = Math.round((grossPaisa * commissionBps) / 10000);
  const vatPaisa = Math.round((grossPaisa * vatBps) / 10000);
  return { grossPaisa, commissionPaisa, vatPaisa, netPaisa: grossPaisa - commissionPaisa - vatPaisa };
}

/** Silver after `silverSales` paid course sales, Gold after `goldSales`. */
export function tierFor(sales: number, s: Pick<PlatformSettings, 'silverSales' | 'goldSales'>): Tier {
  if (sales >= s.goldSales) return 'GOLD';
  if (sales >= s.silverSales) return 'SILVER';
  return null;
}

export function courseCommissionFor(tier: Tier, s: Pick<PlatformSettings, 'courseCommissionBps' | 'silverCourseCommissionBps' | 'goldCourseCommissionBps'>) {
  return tier === 'GOLD' ? s.goldCourseCommissionBps : tier === 'SILVER' ? s.silverCourseCommissionBps : s.courseCommissionBps;
}

/** Paid, not refunded sales of an instructor's recorded courses. */
export async function paidCourseSales(db: Db, teacherId: string): Promise<number> {
  const courses = await db.course.findMany({ where: { teacherId }, select: { id: true } });
  if (!courses.length) return 0;
  return db.order.count({ where: { itemType: 'COURSE', status: 'PAID', itemId: { in: courses.map((c) => c.id) } } });
}

export function settingsOf(db: Db) {
  return db.platformSettings.upsert({ where: { id: 1 }, create: { id: 1 }, update: {} });
}
