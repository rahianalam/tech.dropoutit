import { BadRequestException, ForbiddenException, Injectable } from '@nestjs/common';
import { PlatformSettings, StoragePlan, TeacherProfile } from '@prisma/client';
import { courseCommissionFor, paidCourseSales, settingsOf, tierFor } from '../fees/fees';
import { PaymentsService } from '../payments/payments.service';
import { PrismaService } from '../prisma/prisma.service';

export const PLAN_ORDER: StoragePlan[] = ['FREE', 'STARTER', 'PRO', 'UNLIMITED'];

/** Videos allowed on a plan (null = no limit). An expired plan falls back to the free limit. */
export function videoLimit(p: Pick<TeacherProfile, 'storagePlan' | 'storagePlanUntil'>, s: PlatformSettings, now = new Date()): number | null {
  const plan = p.storagePlan !== 'FREE' && p.storagePlanUntil && p.storagePlanUntil > now ? p.storagePlan : 'FREE';
  return { FREE: s.freeVideoLimit, STARTER: s.starterVideoLimit, PRO: s.proVideoLimit, UNLIMITED: null }[plan];
}

export function planPrice(plan: StoragePlan, s: PlatformSettings): number {
  return { FREE: 0, STARTER: s.starterPricePaisa, PRO: s.proPricePaisa, UNLIMITED: s.unlimitedPricePaisa }[plan];
}

/** Yearly = 10 months' price (2 months free). */
export function planTotal(plan: StoragePlan, months: 1 | 12, s: PlatformSettings) {
  return planPrice(plan, s) * (months === 12 ? 10 : 1);
}

@Injectable()
export class InstructorService {
  constructor(
    private prisma: PrismaService,
    private payments: PaymentsService,
  ) {}

  private async isAdmin(userId: string) {
    return !!(await this.prisma.userRole.findUnique({ where: { userId_role: { userId, role: 'ADMIN' } } }));
  }

  /** Free courses published, lesson plays and minutes watched: the blue-tick targets. */
  async progress(teacherId: string) {
    const [freeCourses, views, watched] = await Promise.all([
      this.prisma.course.count({ where: { teacherId, isFree: true, status: 'PUBLISHED' } }),
      this.prisma.course.aggregate({ where: { teacherId }, _sum: { views: true } }),
      this.prisma.lessonProgress.aggregate({ where: { lesson: { section: { course: { teacherId } } } }, _sum: { watchedSec: true } }),
    ]);
    return { freeCourses, views: views._sum.views ?? 0, watchMinutes: Math.floor((watched._sum.watchedSec ?? 0) / 60) };
  }

  /** Grants the blue tick (and paid courses) once every target is reached. */
  async maybeVerify(teacherId: string) {
    const profile = await this.prisma.teacherProfile.findUnique({ where: { userId: teacherId } });
    if (!profile || profile.canSellPaid) return profile;
    const s = await settingsOf(this.prisma);
    const p = await this.progress(teacherId);
    if (p.freeCourses < s.freeCoursesRequired || p.views < s.viewsRequired || p.watchMinutes < s.watchMinutesRequired) return profile;
    const updated = await this.prisma.teacherProfile.update({ where: { userId: teacherId }, data: { verifiedAt: new Date(), canSellPaid: true } });
    await this.prisma.notification.create({
      data: { userId: teacherId, title: 'অভিনন্দন! ব্লু টিক পেয়েছেন', body: 'এখন থেকে আপনি পেইড কোর্স দিতে পারবেন।' },
    });
    return updated;
  }

  async status(teacherId: string) {
    const profile = (await this.maybeVerify(teacherId)) ?? (await this.prisma.teacherProfile.findUnique({ where: { userId: teacherId } }));
    const s = await settingsOf(this.prisma);
    const [sales, progress, videos] = await Promise.all([paidCourseSales(this.prisma, teacherId), this.progress(teacherId), this.videoCount(teacherId)]);
    const tier = tierFor(sales, s);
    const official = await this.isAdmin(teacherId);
    return {
      profile,
      official,
      tier,
      sales,
      nextTier: tier === 'GOLD' ? null : tier === 'SILVER' ? { name: 'GOLD', at: s.goldSales } : { name: 'SILVER', at: s.silverSales },
      fees: {
        courseCommissionBps: profile?.courseCommissionBps ?? courseCommissionFor(tier, s),
        sessionCommissionBps: profile?.sessionCommissionBps ?? s.sessionCommissionBps,
        vatBps: s.vatBps,
        silverCourseCommissionBps: s.silverCourseCommissionBps,
        goldCourseCommissionBps: s.goldCourseCommissionBps,
        regularCourseCommissionBps: s.courseCommissionBps,
      },
      verification: {
        verified: !!profile?.verifiedAt,
        canSellPaid: official || !!profile?.canSellPaid,
        ...progress,
        targets: { freeCourses: s.freeCoursesRequired, views: s.viewsRequired, watchMinutes: s.watchMinutesRequired },
      },
      storage: {
        plan: profile && profile.storagePlanUntil && profile.storagePlanUntil > new Date() ? profile.storagePlan : 'FREE',
        until: profile?.storagePlanUntil ?? null,
        videos,
        limit: official || !profile ? null : videoLimit(profile, s),
        plans: PLAN_ORDER.map((plan) => ({
          plan,
          videos: { FREE: s.freeVideoLimit, STARTER: s.starterVideoLimit, PRO: s.proVideoLimit, UNLIMITED: null }[plan],
          monthlyPaisa: planPrice(plan, s),
          yearlyPaisa: planTotal(plan, 12, s),
        })),
      },
    };
  }

  /** The rules a new instructor must accept before applying. */
  async rules() {
    const s = await settingsOf(this.prisma);
    return {
      sessionCommissionBps: s.sessionCommissionBps,
      courseCommissionBps: s.courseCommissionBps,
      silverCourseCommissionBps: s.silverCourseCommissionBps,
      goldCourseCommissionBps: s.goldCourseCommissionBps,
      vatBps: s.vatBps,
      holdDays: s.holdDays,
      silverSales: s.silverSales,
      goldSales: s.goldSales,
      freeCoursesRequired: s.freeCoursesRequired,
      viewsRequired: s.viewsRequired,
      watchMinutesRequired: s.watchMinutesRequired,
      freeVideoLimit: s.freeVideoLimit,
      bookingResponseHours: s.bookingResponseHours,
      plans: PLAN_ORDER.filter((p) => p !== 'FREE').map((plan) => ({ plan, monthlyPaisa: planPrice(plan, s) })),
    };
  }

  videoCount(teacherId: string) {
    return this.prisma.lesson.count({ where: { mediaKey: { startsWith: 'upload:' }, section: { course: { teacherId } } } });
  }

  /** New instructors upload free courses until they have the blue tick. */
  async assertCanSellPaid(teacherId: string) {
    if (await this.isAdmin(teacherId)) return;
    const profile = await this.maybeVerify(teacherId);
    if (profile?.canSellPaid) return;
    const s = await settingsOf(this.prisma);
    throw new BadRequestException(
      `Paid courses unlock with the blue tick: publish ${s.freeCoursesRequired} free courses and reach ${s.viewsRequired} views and ${s.watchMinutesRequired} minutes of watch time.`,
    );
  }

  /** More than the plan's video limit needs a storage plan. Replacing an existing video is always allowed. */
  async assertVideoQuota(teacherId: string, replacing: boolean) {
    if (replacing || (await this.isAdmin(teacherId))) return;
    const profile = await this.prisma.teacherProfile.findUnique({ where: { userId: teacherId } });
    if (!profile) return;
    const limit = videoLimit(profile, await settingsOf(this.prisma));
    if (limit !== null && (await this.videoCount(teacherId)) >= limit) {
      throw new ForbiddenException({ message: `Your plan allows ${limit} videos. Buy a storage plan to upload more.`, code: 'STORAGE_LIMIT' });
    }
  }

  updateProfile(teacherId: string, dto: { headline?: string; bio?: string; skills?: string[]; experience?: string; expertise?: string[]; hourlyRateBdt?: number }) {
    const { hourlyRateBdt, ...rest } = dto;
    return this.prisma.teacherProfile.update({
      where: { userId: teacherId },
      data: { ...rest, ...(hourlyRateBdt !== undefined ? { hourlyRatePaisa: hourlyRateBdt * 100 } : {}) },
    });
  }

  async buyPlan(teacherId: string, plan: StoragePlan, months: 1 | 12) {
    if (plan === 'FREE') throw new BadRequestException('The free plan needs no purchase');
    const s = await settingsOf(this.prisma);
    return this.payments.checkoutItem(teacherId, 'STORAGE_PLAN', `${plan}:${months}`, planTotal(plan, months, s), `Storage plan ${plan} (${months} month${months > 1 ? 's' : ''})`);
  }

  /** Admin gives (or takes away) the blue tick by hand, e.g. for a known instructor. */
  async setVerified(teacherId: string, adminId: string, verified: boolean) {
    const updated = await this.prisma.teacherProfile.update({
      where: { userId: teacherId },
      data: verified ? { verifiedAt: new Date(), canSellPaid: true } : { verifiedAt: null, canSellPaid: false },
    });
    await this.prisma.auditLog.create({ data: { actorId: adminId, action: verified ? 'teacher.verify' : 'teacher.unverify', target: teacherId } });
    if (verified) await this.prisma.notification.create({ data: { userId: teacherId, title: 'ব্লু টিক পেয়েছেন', body: 'এখন থেকে আপনি পেইড কোর্স দিতে পারবেন।' } });
    return updated;
  }

  /** Every earning with its fee breakdown, newest first. */
  earnings(teacherId: string) {
    return this.prisma.ledgerEntry.findMany({
      where: { teacherId, type: 'EARNING' },
      orderBy: { createdAt: 'desc' },
      take: 100,
      include: { order: { select: { itemType: true, itemId: true, tranId: true, paidAt: true } } },
    });
  }
}
