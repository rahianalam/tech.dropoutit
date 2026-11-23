import { Body, Controller, Delete, HttpCode, Injectable, Logger, Module, Param, Post } from '@nestjs/common';
import { Interval } from '@nestjs/schedule';
import { DevicePlatform } from '@prisma/client';
import { IsEnum, IsString, Length } from 'class-validator';
import { AuthUser, CurrentUser } from '../common/auth.decorators';
import { PrismaService } from '../prisma/prisma.service';
import { FcmClient } from './fcm';

class DeviceDto {
  @IsString() @Length(20, 4096) token: string;
  @IsEnum(DevicePlatform) platform: DevicePlatform;
}

@Controller('me/devices')
export class DevicesController {
  constructor(private prisma: PrismaService) {}

  /** A token belongs to one phone; if someone else signs in on it, it moves to them. */
  @Post() @HttpCode(204)
  async register(@CurrentUser() u: AuthUser, @Body() dto: DeviceDto) {
    await this.prisma.deviceToken.upsert({
      where: { token: dto.token },
      create: { token: dto.token, userId: u.id, platform: dto.platform },
      update: { userId: u.id, platform: dto.platform, lastSeenAt: new Date() },
    });
  }

  @Delete(':token') @HttpCode(204)
  async remove(@CurrentUser() u: AuthUser, @Param('token') token: string) {
    await this.prisma.deviceToken.deleteMany({ where: { token, userId: u.id } });
  }
}

/**
 * Every in-app notification is also sent as a push. Instead of touching every
 * place that creates notifications, this picks up new rows every few seconds.
 * Rows are claimed before sending so two API instances never double-send.
 */
@Injectable()
export class PushService {
  private log = new Logger('Push');
  private enabled = process.env.SCHEDULER_DISABLED !== 'true';
  private running = false;

  constructor(private prisma: PrismaService, private fcm: FcmClient) {}

  @Interval(10_000)
  async tick() {
    if (!this.enabled || this.running || !this.fcm.enabled) return;
    this.running = true;
    try {
      await this.sendPending();
    } catch (e) {
      this.log.error((e as Error).message);
    } finally {
      this.running = false;
    }
  }

  async sendPending(now = new Date()) {
    // Only recent ones: turning push on later must not flood phones with old news.
    const since = new Date(now.getTime() - 10 * 60_000);
    const batch = await this.prisma.notification.findMany({
      where: { pushedAt: null, createdAt: { gte: since } },
      orderBy: { createdAt: 'asc' },
      take: 200,
    });
    if (!batch.length) return 0;
    const ids = batch.map((n) => n.id);
    const claim = new Date(now.getTime() + Math.floor(Math.random() * 1000)); // unique enough per instance
    await this.prisma.notification.updateMany({ where: { id: { in: ids }, pushedAt: null }, data: { pushedAt: claim } });
    const mine = new Set((await this.prisma.notification.findMany({ where: { id: { in: ids }, pushedAt: claim }, select: { id: true } })).map((n) => n.id));
    batch.splice(0, batch.length, ...batch.filter((n) => mine.has(n.id)));
    const devices = await this.prisma.deviceToken.findMany({ where: { userId: { in: [...new Set(batch.map((n) => n.userId))] } } });
    let sent = 0;
    for (const n of batch) {
      for (const d of devices.filter((x) => x.userId === n.userId)) {
        const r = await this.fcm.send(d.token, n.title, n.body, { notificationId: n.id });
        if (r === 'ok') sent++;
        if (r === 'invalid-token') await this.prisma.deviceToken.deleteMany({ where: { token: d.token } });
      }
    }
    return sent;
  }
}

@Module({ controllers: [DevicesController], providers: [FcmClient, PushService], exports: [FcmClient, PushService] })
export class PushModule {}
