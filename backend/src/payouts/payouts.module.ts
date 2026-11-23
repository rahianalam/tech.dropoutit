import { Body, Controller, Delete, Get, HttpCode, Injectable, Logger, Module, Param, ParseUUIDPipe, Patch, Post, Query } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { IsIn, IsString, Length } from 'class-validator';
import { AuthUser, CurrentUser, Roles } from '../common/auth.decorators';
import { PaymentsModule } from '../payments/payments.module';
import { PaymentsService } from '../payments/payments.service';
import { PrismaService } from '../prisma/prisma.service';
import { isPayoutDay, PayoutsService } from './payouts.service';

class PayoutAccountDto {
  @IsIn(['bkash', 'nagad', 'rocket', 'bank']) method: string;
  @IsString() @Length(5, 200) account: string;
}

class MarkPaidDto {
  @IsString() @Length(3, 120) reference: string;
}

@Controller()
export class PayoutsController {
  constructor(
    private payouts: PayoutsService,
    private prisma: PrismaService,
  ) {}

  @Roles('TEACHER') @Get('teacher/earnings')
  earnings(@CurrentUser() u: AuthUser) { return this.payouts.earnings(u.id); }

  @Roles('TEACHER') @Patch('teacher/payout-account')
  account(@CurrentUser() u: AuthUser, @Body() dto: PayoutAccountDto) {
    return this.prisma.teacherProfile.update({
      where: { userId: u.id },
      data: { payoutMethod: dto.method, payoutAccount: dto.account },
      select: { payoutMethod: true, payoutAccount: true },
    });
  }

  @Roles('ADMIN') @Get('admin/payouts')
  list(@Query('status') status?: 'DRAFT' | 'APPROVED' | 'PAID') { return this.payouts.list(status); }

  @Roles('ADMIN') @Post('admin/payouts/generate')
  generate() { return this.payouts.generateDrafts(); }

  @Roles('ADMIN') @Post('admin/payouts/:id/approve')
  approve(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) { return this.payouts.approve(id, u.id); }

  @Roles('ADMIN') @Post('admin/payouts/:id/paid')
  paid(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser, @Body() dto: MarkPaidDto) {
    return this.payouts.markPaid(id, u.id, dto.reference);
  }

  @Roles('ADMIN') @Delete('admin/payouts/:id') @HttpCode(204)
  cancel(@Param('id', ParseUUIDPipe) id: string) { return this.payouts.cancel(id); }

  @Roles('ADMIN') @Get('admin/revenue')
  revenue() { return this.payouts.revenue(); }
}

/** Background jobs. Set SCHEDULER_DISABLED=true to turn them off (tests, extra API replicas). */
@Injectable()
export class MoneyJobs {
  private log = new Logger('MoneyJobs');
  private enabled = process.env.SCHEDULER_DISABLED !== 'true';
  constructor(
    private payments: PaymentsService,
    private payouts: PayoutsService,
    private prisma: PrismaService,
  ) {}

  @Cron(CronExpression.EVERY_5_MINUTES)
  async expireOrders() {
    if (this.enabled) await this.payments.expireStale();
  }

  @Cron(CronExpression.EVERY_HOUR)
  async release() {
    if (this.enabled) await this.payouts.releaseMatured();
  }

  /** 09:00 Dhaka: on a payout day, draft payouts for the admin to approve. */
  @Cron('0 9 * * *', { timeZone: 'Asia/Dhaka' })
  async draftPayouts() {
    if (!this.enabled) return;
    const s = await this.prisma.platformSettings.upsert({ where: { id: 1 }, create: { id: 1 }, update: {} });
    if (!isPayoutDay(s.payoutSchedule, s.payoutDayOfMonth)) return;
    const drafts = await this.payouts.generateDrafts();
    this.log.log(`drafted ${drafts.length} payouts`);
  }
}

@Module({
  imports: [PaymentsModule],
  controllers: [PayoutsController],
  providers: [PayoutsService, MoneyJobs],
})
export class PayoutsModule {}
