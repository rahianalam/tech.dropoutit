import { Body, Controller, Get, Injectable, Module, Param, ParseUUIDPipe, Post, Put, Query } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { Type } from 'class-transformer';
import { ArrayMaxSize, IsDateString, IsIn, IsInt, IsOptional, IsString, IsUUID, Length, Max, Min, ValidateNested } from 'class-validator';
import { AuthUser, CurrentUser, Public, Roles } from '../common/auth.decorators';
import { PaymentsModule } from '../payments/payments.module';
import { BookingsService } from './bookings.service';

class RuleDto {
  @IsInt() @Min(0) @Max(6) weekday: number;
  @IsInt() @Min(0) @Max(1440) startMinute: number;
  @IsInt() @Min(0) @Max(1440) endMinute: number;
  @IsIn([30, 45, 60, 90, 120]) slotMinutes: number;
  /** BDT per slot; 0 = free intro session. Paid slots are priced from the hourly rate when one is set. */
  @IsInt() @Min(0) @Max(100000) priceBdt: number;
}
class RulesDto {
  @ValidateNested({ each: true }) @Type(() => RuleDto) @ArrayMaxSize(50) rules: RuleDto[];
}
class BookDto {
  @IsUUID() teacherId: string;
  @IsDateString() startAt: string;
}
class OutcomeDto {
  @IsIn(['COMPLETED', 'NO_SHOW']) outcome: 'COMPLETED' | 'NO_SHOW';
}
class DeclineDto {
  @IsOptional() @IsString() @Length(0, 500) note?: string;
}
class ReportDto {
  @IsString() @Length(5, 1000) reason: string;
}
export class ReviewDto {
  @IsInt() @Min(1) @Max(5) rating: number;
  @IsOptional() @IsString() @Length(0, 2000) comment?: string;
}

const Id = () => Param('id', ParseUUIDPipe);

@Controller()
export class BookingsController {
  constructor(private bookings: BookingsService) {}

  @Roles('TEACHER') @Get('teacher/availability')
  rules(@CurrentUser() u: AuthUser) { return this.bookings.rules(u.id); }

  @Roles('TEACHER') @Put('teacher/availability')
  setRules(@CurrentUser() u: AuthUser, @Body() dto: RulesDto) {
    return this.bookings.setRules(u.id, dto.rules.map(({ priceBdt, ...r }) => ({ ...r, pricePaisa: priceBdt * 100 })));
  }

  @Roles('TEACHER') @Post('teacher/bookings/:id/accept')
  accept(@Id() id: string, @CurrentUser() u: AuthUser) { return this.bookings.accept(id, u); }

  @Roles('TEACHER') @Post('teacher/bookings/:id/decline')
  decline(@Id() id: string, @CurrentUser() u: AuthUser, @Body() dto: DeclineDto) { return this.bookings.decline(id, u, dto.note); }

  @Roles('TEACHER') @Get('teacher/bookings')
  teacherBookings(@CurrentUser() u: AuthUser) { return this.bookings.forTeacher(u.id); }

  @Public() @Get('teachers/:id/slots')
  slots(@Id() id: string, @Query('days') days?: string) { return this.bookings.slots(id, Math.max(1, Math.min(30, Number(days) || 14))); }

  @Post('bookings')
  book(@CurrentUser() u: AuthUser, @Body() dto: BookDto) { return this.bookings.book(u, dto.teacherId, new Date(dto.startAt)); }

  @Get('me/bookings')
  mine(@CurrentUser() u: AuthUser) { return this.bookings.mine(u.id); }

  @Post('bookings/:id/cancel')
  cancel(@Id() id: string, @CurrentUser() u: AuthUser) { return this.bookings.cancel(id, u); }

  @Post('bookings/:id/complete')
  complete(@Id() id: string, @CurrentUser() u: AuthUser, @Body() dto: OutcomeDto) { return this.bookings.complete(id, u, dto.outcome); }

  @Post('bookings/:id/report')
  report(@Id() id: string, @CurrentUser() u: AuthUser, @Body() dto: ReportDto) { return this.bookings.report(id, u, dto.reason); }

  @Post('bookings/:id/review')
  review(@Id() id: string, @CurrentUser() u: AuthUser, @Body() dto: ReviewDto) { return this.bookings.reviewBooking(id, u, dto.rating, dto.comment); }
}

@Injectable()
export class BookingJobs {
  private enabled = process.env.SCHEDULER_DISABLED !== 'true';
  constructor(private bookings: BookingsService) {}

  @Cron(CronExpression.EVERY_MINUTE)
  async tick() {
    if (!this.enabled) return;
    await this.bookings.releaseExpiredHolds();
    await this.bookings.expireRequests();
    await this.bookings.sendReminders();
  }

  @Cron(CronExpression.EVERY_HOUR)
  async complete() {
    if (this.enabled) await this.bookings.autoComplete();
  }
}

@Module({ imports: [PaymentsModule], controllers: [BookingsController], providers: [BookingsService, BookingJobs] })
export class BookingsModule {}
