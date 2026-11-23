import { Body, Controller, Get, Injectable, Module, Patch } from '@nestjs/common';
import { PayoutSchedule } from '@prisma/client';
import { IsEnum, IsInt, IsOptional, Max, Min } from 'class-validator';
import { AuthUser, CurrentUser, Roles } from '../common/auth.decorators';
import { PrismaService } from '../prisma/prisma.service';

/** Every money rule is editable by the admin; defaults are the plan's guesses (30% / 20% / 7 days / monthly / 1,000 BDT). */
class UpdateSettingsDto {
  @IsOptional() @IsInt() @Min(0) @Max(9000) courseCommissionBps?: number;
  @IsOptional() @IsInt() @Min(0) @Max(9000) sessionCommissionBps?: number;
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
