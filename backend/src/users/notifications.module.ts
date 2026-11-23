import { Controller, Get, HttpCode, Module, Post } from '@nestjs/common';
import { AuthUser, CurrentUser } from '../common/auth.decorators';
import { PrismaService } from '../prisma/prisma.service';

@Controller('me/notifications')
export class NotificationsController {
  constructor(private prisma: PrismaService) {}

  @Get()
  list(@CurrentUser() u: AuthUser) {
    return this.prisma.notification.findMany({ where: { userId: u.id }, orderBy: { createdAt: 'desc' }, take: 50 });
  }

  @Post('read-all') @HttpCode(204)
  async readAll(@CurrentUser() u: AuthUser) {
    await this.prisma.notification.updateMany({ where: { userId: u.id, readAt: null }, data: { readAt: new Date() } });
  }
}

@Module({ controllers: [NotificationsController] })
export class NotificationsModule {}
