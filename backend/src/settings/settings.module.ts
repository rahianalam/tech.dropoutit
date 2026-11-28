import { Body, Controller, Get, Injectable, Module, Patch } from '@nestjs/common';
import { PayoutSchedule } from '@prisma/client';
import { IsEnum, IsInt, IsOptional, Max, Min } from 'class-validator';
import { AuthUser, CurrentUser, Roles } from '../common/auth.decorators';
import { PrismaService } from '../prisma/prisma.service';

const bps = () => (t: object, k: string) => { IsOptional()(t, k); IsInt()(t, k); Min(0)(t, k); Max(9000)(t, k); };
const count = () => (t: object, k: string) => { IsOptional()(t, k); IsInt()(t, k); Min(0)(t, k); Max(10_000_000)(t, k); };

/** Every money rule is editable by the admin (defaults: 7% / 6% / 5% on courses by tier, 10% on bookings, 5% VAT). */
class UpdateSettingsDto {
  @bps() courseCommissionBps?: number;
  @bps() silverCourseCommissionBps?: number;
  @bps() goldCourseCommissionBps?: number;
  @bps() sessionCommissionBps?: number;
  @bps() vatBps?: number;
  @bps() affiliateCommissionBps?: number;
  @count() silverSales?: number;
  @count() goldSales?: number;
  @count() bookingResponseHours?: number;
  @count() freeCoursesRequired?: number;
  @count() viewsRequired?: number;
  @count() watchMinutesRequired?: number;
  @count() freeVideoLimit?: number;
  @count() starterVideoLimit?: number;
  @count() proVideoLimit?: number;
  @count() starterPricePaisa?: number;
  @count() proPricePaisa?: number;
  @count() unlimitedPricePaisa?: number;
  /** At least 1: the reward is given per `referralTarget` friends. */
  @IsOptional() @IsInt() @Min(1) @Max(10_000) referralTarget?: number;
  @count() referralPassDays?: number;
  @count() affiliateFeePaisa?: number;
  @count() affiliateInactiveDays?: number;
  @IsOptional() @IsInt() @Min(0) @Max(90) holdDays?: number;
  @IsOptional() @IsEnum(PayoutSchedule) payoutSchedule?: PayoutSchedule;
  @IsOptional() @IsInt() @Min(1) @Max(28) payoutDayOfMonth?: number;
  @IsOptional() @IsInt() @Min(0) minPayoutPaisa?: number;
}

@Injectable()
export class SettingsService {
  constructor(private prisma: PrismaService) {}
  get() {
    return this.prisma.platformSettings.upsert({ where: { id: 1 }, create: { id: 1 }, update: {} });
  }
  async update(adminId: string, dto: UpdateSettingsDto) {
    await this.get();
    const updated = await this.prisma.platformSettings.update({ where: { id: 1 }, data: dto });
    await this.prisma.auditLog.create({ data: { actorId: adminId, action: 'settings.update', target: 'platform', meta: dto as object } });
    return updated;
  }
}

@Controller('admin/settings')
export class SettingsController {
  constructor(private settings: SettingsService) {}
  @Roles('ADMIN') @Get() get() { return this.settings.get(); }
  @Roles('ADMIN') @Patch() update(@CurrentUser() u: AuthUser, @Body() dto: UpdateSettingsDto) { return this.settings.update(u.id, dto); }
}

@Module({ controllers: [SettingsController], providers: [SettingsService], exports: [SettingsService] })
export class SettingsModule {}
