import { BadRequestException, Body, ConflictException, Controller, ForbiddenException, Get, Injectable, Module, NotFoundException, Param, ParseUUIDPipe, Post, Put, Query } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { AffiliateStatus } from '@prisma/client';
import { randomBytes } from 'crypto';
import { IsEnum, IsIn, IsOptional, IsString, IsUUID, Length, Matches } from 'class-validator';
import { AuthUser, CurrentUser, Public, Roles } from '../common/auth.decorators';
import { settingsOf } from '../fees/fees';
import { PaymentsModule } from '../payments/payments.module';
import { PaymentsService } from '../payments/payments.service';
import { PrismaService } from '../prisma/prisma.service';
import { UploadsModule, UploadsService } from '../uploads/uploads.module';

const code = (len = 7) => randomBytes(8).toString('base64').replace(/[^A-Z0-9]/gi, '').toUpperCase().slice(0, len).padEnd(len, 'X');

class VerificationDto {
  @Matches(/^\d{10}$|^\d{13}$|^\d{17}$/, { message: 'NID number must have 10, 13 or 17 digits' }) nidNumber: string;
  @IsUUID() nidFrontId: string;
  @IsUUID() nidBackId: string;
  @IsUUID() photoId: string;
  @IsUUID() selfieId: string;
}
class PayoutDto {
  @IsIn(['bkash', 'nagad', 'rocket', 'bank']) method: string;
  @IsString() @Length(5, 200) account: string;
}
class ReviewDto {
  @IsIn(['APPROVED', 'REJECTED']) decision: 'APPROVED' | 'REJECTED';
  @IsOptional() @IsString() @Length(0, 1000) note?: string;
}
class ClickDto {
  @IsString() @Length(4, 20) code: string;
  @IsOptional() @IsUUID() courseId?: string;
}
class StatusQuery {
  @IsOptional() @IsEnum(AffiliateStatus) status?: AffiliateStatus;
}

@Injectable()
export class GrowthService {
  constructor(
    private prisma: PrismaService,
    private payments: PaymentsService,
    private uploads: UploadsService,
  ) {}

  // ---------- referrals ----------

  /** The student's invite code (made on first use) and progress toward the next reward. */
  async referral(userId: string) {
    let user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    while (!user.referralCode) {
      user = await this.prisma.user.update({ where: { id: userId }, data: { referralCode: code(6) } }).catch(() => user);
    }
    const s = await settingsOf(this.prisma);
    const [joined, qualified] = await Promise.all([
      this.prisma.user.count({ where: { referredById: userId } }),
      this.prisma.user.count({ where: { referredById: userId, orders: { some: { itemType: 'COURSE', status: 'PAID' } } } }),
    ]);
    return {
      code: user.referralCode,
      joined,
      qualified,
      target: s.referralTarget,
      passDays: s.referralPassDays,
      towardNext: qualified - user.referralRewards * s.referralTarget,
      freePassUntil: user.freePassUntil && user.freePassUntil > new Date() ? user.freePassUntil : null,
    };
  }

  // ---------- affiliates ----------

  async join(userId: string) {
    const existing = await this.prisma.affiliateProfile.findUnique({ where: { userId } });
    if (existing) return existing;
    for (;;) {
      try {
        const profile = await this.prisma.affiliateProfile.create({ data: { userId, code: code() } });
        await this.prisma.userRole.upsert({ where: { userId_role: { userId, role: 'AFFILIATE' } }, create: { userId, role: 'AFFILIATE' }, update: {} });
        return profile;
      } catch (e) {
        if ((e as { code?: string }).code !== 'P2002') throw e;
      }
    }
  }

  private async mine(userId: string) {
    const a = await this.prisma.affiliateProfile.findUnique({ where: { userId } });
    if (!a) throw new NotFoundException('Join the affiliate program first');
    return a;
  }

  async payMembership(userId: string) {
    const a = await this.mine(userId);
    if (a.membershipPaidAt && a.status !== 'DEACTIVATED') throw new ConflictException('Membership is already paid');
    const s = await settingsOf(this.prisma);
    return this.payments.checkoutItem(userId, 'AFFILIATE_MEMBERSHIP', userId, s.affiliateFeePaisa, 'Tech.Dropout affiliate membership');
  }

  /** NID front/back, a photo and a live selfie, all uploaded as private KYC files by this user. */
  async submitVerification(userId: string, dto: VerificationDto) {
    const a = await this.mine(userId);
    if (a.status === 'ACTIVE') throw new ConflictException('Your account is already verified');
    const ids = [dto.nidFrontId, dto.nidBackId, dto.photoId, dto.selfieId];
    const files = await this.prisma.upload.count({ where: { id: { in: ids }, ownerId: userId, kind: 'KYC' } });
    if (files !== 4) throw new BadRequestException('Upload all four pictures first');
    return this.prisma.affiliateProfile.update({
      where: { userId },
      data: { ...dto, adminNote: null, status: a.membershipPaidAt ? 'IN_REVIEW' : 'UNPAID' },
    });
  }

  setPayout(userId: string, dto: PayoutDto) {
    return this.prisma.affiliateProfile.update({ where: { userId }, data: { payoutMethod: dto.method, payoutAccount: dto.account } });
  }

  /** Dashboard: status, link code, 30-day clicks and sales by day, and money by state. */
  async dashboard(userId: string) {
    const a = await this.prisma.affiliateProfile.update({ where: { userId }, data: { lastActiveAt: new Date() } }).catch(() => null);
    if (!a) throw new NotFoundException('Join the affiliate program first');
    const since = new Date(Date.now() - 30 * 864e5);
    const s = await settingsOf(this.prisma);
    const [clicks, earnings, byStatus, totalClicks] = await Promise.all([
      this.prisma.affiliateClick.findMany({ where: { affiliateId: userId, createdAt: { gte: since } }, select: { createdAt: true } }),
      this.prisma.affiliateEarning.findMany({ where: { affiliateId: userId }, orderBy: { createdAt: 'desc' }, take: 50 }),
      this.prisma.affiliateEarning.groupBy({ by: ['status'], where: { affiliateId: userId }, _sum: { amountPaisa: true }, _count: true }),
      this.prisma.affiliateClick.count({ where: { affiliateId: userId } }),
    ]);
    const days = [...Array(30)].map((_, i) => new Date(Date.now() - (29 - i) * 864e5).toISOString().slice(0, 10));
    const perDay = days.map((d) => ({
      day: d,
      clicks: clicks.filter((c) => c.createdAt.toISOString().startsWith(d)).length,
      sales: earnings.filter((e) => e.createdAt.toISOString().startsWith(d)).length,
    }));
    const courses = await this.prisma.course.findMany({ where: { id: { in: earnings.map((e) => e.courseId) } }, select: { id: true, title: true } });
    const sum = (st: string) => byStatus.find((b) => b.status === st)?._sum.amountPaisa ?? 0;
    const sales = byStatus.filter((b) => b.status !== 'VOID').reduce((n, b) => n + b._count, 0);
    const { nidFrontId, nidBackId, photoId, selfieId, ...profile } = a;
    return {
      profile: { ...profile, documentsSent: !!(nidFrontId && nidBackId && photoId && selfieId) },
      rules: { commissionBps: s.affiliateCommissionBps, feePaisa: s.affiliateFeePaisa, inactiveDays: s.affiliateInactiveDays, holdDays: s.holdDays },
      totals: { clicks: totalClicks, clicks30: clicks.length, sales, conversionPct: totalClicks ? Math.round((sales / totalClicks) * 1000) / 10 : 0 },
      money: { pendingPaisa: sum('PENDING'), availablePaisa: sum('AVAILABLE'), paidPaisa: sum('PAID') },
      perDay,
      recent: earnings.map((e) => ({ ...e, courseTitle: courses.find((c) => c.id === e.courseId)?.title })),
    };
  }

  /** A visit through an affiliate link (counted only for live affiliates). */
  async click(dto: ClickDto) {
    const a = await this.prisma.affiliateProfile.findUnique({ where: { code: dto.code.trim().toUpperCase() } });
    if (!a || a.status !== 'ACTIVE') return { counted: false };
    await this.prisma.affiliateClick.create({ data: { affiliateId: a.userId, courseId: dto.courseId } });
    return { counted: true };
  }

  // ---------- admin ----------

  list(status?: AffiliateStatus) {
    return this.prisma.affiliateProfile.findMany({
      where: status ? { status } : {},
      orderBy: { updatedAt: 'desc' },
      take: 200,
      include: { user: { select: { id: true, name: true, email: true, phone: true } } },
    });
  }

  async get(userId: string) {
    const a = await this.prisma.affiliateProfile.findUnique({ where: { userId }, include: { user: { select: { id: true, name: true, email: true, phone: true } } } });
    if (!a) throw new NotFoundException();
    const link = (id: string | null) => (id ? this.uploads.link(id, 15 * 60) : null);
    const available = await this.prisma.affiliateEarning.aggregate({ where: { affiliateId: userId, status: 'AVAILABLE' }, _sum: { amountPaisa: true } });
    return {
      ...a,
      documents: { nidFront: link(a.nidFrontId), nidBack: link(a.nidBackId), photo: link(a.photoId), selfie: link(a.selfieId) },
      availablePaisa: available._sum.amountPaisa ?? 0,
    };
  }

  async review(userId: string, adminId: string, dto: ReviewDto) {
    const a = await this.prisma.affiliateProfile.findUnique({ where: { userId } });
    if (!a) throw new NotFoundException();
    if (dto.decision === 'REJECTED' && !dto.note) throw new BadRequestException('Write why, so the affiliate can fix it');
    if (dto.decision === 'APPROVED' && !a.membershipPaidAt) throw new BadRequestException('The membership fee is not paid yet');
    const updated = await this.prisma.affiliateProfile.update({
      where: { userId },
      data: { status: dto.decision === 'APPROVED' ? 'ACTIVE' : 'REJECTED', adminNote: dto.note, lastActiveAt: new Date() },
    });
    await this.prisma.notification.create({
      data: {
        userId,
        title: dto.decision === 'APPROVED' ? 'অ্যাফিলিয়েট অ্যাকাউন্ট চালু' : 'অ্যাফিলিয়েট ভেরিফিকেশন হয়নি',
        body: dto.decision === 'APPROVED' ? 'এখন থেকে আপনার লিংক দিয়ে বিক্রি হলে আয় পাবেন।' : `কারণ: ${dto.note}। ছবিগুলো আবার পাঠান।`,
      },
    });
    await this.prisma.auditLog.create({ data: { actorId: adminId, action: `affiliate.${dto.decision.toLowerCase()}`, target: userId } });
    return updated;
  }

  /** Admin sent the affiliate their available money. */
  async markPaid(userId: string, adminId: string) {
    const res = await this.prisma.affiliateEarning.updateMany({ where: { affiliateId: userId, status: 'AVAILABLE' }, data: { status: 'PAID' } });
    await this.prisma.auditLog.create({ data: { actorId: adminId, action: 'affiliate.paid', target: userId, meta: { entries: res.count } } });
    return { paidEntries: res.count };
  }

  // ---------- scheduled ----------

  /** Money past the hold period becomes withdrawable; affiliates idle for the set days are deactivated. */
  async daily(now = new Date()) {
    const s = await settingsOf(this.prisma);
    const matured = await this.prisma.affiliateEarning.updateMany({ where: { status: 'PENDING', availableAt: { lte: now } }, data: { status: 'AVAILABLE' } });
    const idle = await this.prisma.affiliateProfile.updateMany({
      where: { status: 'ACTIVE', lastActiveAt: { lt: new Date(now.getTime() - s.affiliateInactiveDays * 864e5) } },
      data: { status: 'DEACTIVATED' },
    });
    return { matured: matured.count, deactivated: idle.count };
  }
}

@Controller()
export class GrowthController {
  constructor(private growth: GrowthService) {}

  @Get('me/referral') referral(@CurrentUser() u: AuthUser) { return this.growth.referral(u.id); }

  @Post('affiliates/join') join(@CurrentUser() u: AuthUser) { return this.growth.join(u.id); }
  @Get('affiliates/me') me(@CurrentUser() u: AuthUser) { return this.growth.dashboard(u.id); }
  @Post('affiliates/me/membership') pay(@CurrentUser() u: AuthUser) { return this.growth.payMembership(u.id); }
  @Put('affiliates/me/verification') verify(@CurrentUser() u: AuthUser, @Body() dto: VerificationDto) { return this.growth.submitVerification(u.id, dto); }
  @Put('affiliates/me/payout') payout(@CurrentUser() u: AuthUser, @Body() dto: PayoutDto) { return this.growth.setPayout(u.id, dto); }
  @Public() @Post('affiliates/click') click(@Body() dto: ClickDto) { return this.growth.click(dto); }

  @Roles('ADMIN') @Get('admin/affiliates') list(@Query() q: StatusQuery) { return this.growth.list(q.status); }
  @Roles('ADMIN') @Get('admin/affiliates/:id') get(@Param('id', ParseUUIDPipe) id: string) { return this.growth.get(id); }
  @Roles('ADMIN') @Post('admin/affiliates/:id/review') review(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser, @Body() dto: ReviewDto) {
    return this.growth.review(id, u.id, dto);
  }
  @Roles('ADMIN') @Post('admin/affiliates/:id/paid') paid(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) { return this.growth.markPaid(id, u.id); }
}

@Injectable()
export class GrowthJobs {
  constructor(private growth: GrowthService) {}
  @Cron('30 3 * * *', { timeZone: 'Asia/Dhaka' })
  async daily() {
    if (process.env.SCHEDULER_DISABLED !== 'true') await this.growth.daily();
  }
}

@Module({ imports: [PaymentsModule, UploadsModule], controllers: [GrowthController], providers: [GrowthService, GrowthJobs] })
export class GrowthModule {}
