import { Body, Controller, ForbiddenException, Get, Module, Param, ParseUUIDPipe, Patch, Query } from '@nestjs/common';
import { IsArray, IsEnum, IsOptional } from 'class-validator';
import { Role, UserStatus } from '@prisma/client';
import { AuthUser, CurrentUser, Roles } from '../common/auth.decorators';
import { PrismaService } from '../prisma/prisma.service';

class StatusDto {
  @IsEnum(UserStatus) status: UserStatus;
}

class RolesDto {
  @IsOptional() @IsArray() @IsEnum(Role, { each: true }) add?: Role[];
  @IsOptional() @IsArray() @IsEnum(Role, { each: true }) remove?: Role[];
}

@Controller('admin')
@Roles('ADMIN')
export class AdminController {
  constructor(private prisma: PrismaService) {}

  @Get('stats')
  async stats() {
    const [users, teachers, publishedCourses, enrollments, pendingApplications, coursesInReview, jobsInReview, liveJobs] = await Promise.all([
      this.prisma.user.count(),
      this.prisma.userRole.count({ where: { role: 'TEACHER' } }),
      this.prisma.course.count({ where: { status: 'PUBLISHED' } }),
      this.prisma.enrollment.count({ where: { status: 'ACTIVE' } }),
      this.prisma.teacherApplication.count({ where: { status: 'PENDING' } }),
      this.prisma.course.count({ where: { status: 'IN_REVIEW' } }),
      this.prisma.job.count({ where: { status: 'PENDING' } }),
      this.prisma.job.count({ where: { status: 'LIVE' } }),
    ]);
    const since = new Date(Date.now() - 30 * 864e5);
    const [revenue30, revenueAll, newUsers30, bookings30] = await Promise.all([
      this.prisma.order.aggregate({ where: { status: 'PAID', paidAt: { gte: since } }, _sum: { amountPaisa: true } }),
      this.prisma.order.aggregate({ where: { status: 'PAID' }, _sum: { amountPaisa: true } }),
      this.prisma.user.count({ where: { createdAt: { gte: since } } }),
      this.prisma.booking.count({ where: { createdAt: { gte: since } } }),
    ]);
    return {
      users, teachers, publishedCourses, enrollments, pendingApplications, coursesInReview, jobsInReview, liveJobs,
      revenue30Paisa: revenue30._sum.amountPaisa ?? 0,
      revenueAllPaisa: revenueAll._sum.amountPaisa ?? 0,
      newUsers30,
      bookings30,
    };
  }

  /** Recent admin actions (approvals, status changes, settings), newest first. */
  @Get('audit')
  audit() {
    return this.prisma.auditLog.findMany({ orderBy: { createdAt: 'desc' }, take: 100 });
  }

  /** Give or take away roles, e.g. make someone a teacher or a second admin. */
  @Patch('users/:id/roles')
  async setRoles(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() admin: AuthUser, @Body() dto: RolesDto) {
    if (id === admin.id && dto.remove?.includes('ADMIN')) throw new ForbiddenException('You cannot remove your own admin role');
    for (const role of dto.add ?? []) {
      await this.prisma.userRole.upsert({ where: { userId_role: { userId: id, role } }, create: { userId: id, role }, update: {} });
      if (role === 'TEACHER') {
        await this.prisma.teacherProfile.upsert({ where: { userId: id }, create: { userId: id, headline: 'Instructor', bio: '', skills: [] }, update: {} });
      }
    }
    if (dto.remove?.length) await this.prisma.userRole.deleteMany({ where: { userId: id, role: { in: dto.remove } } });
    await this.prisma.auditLog.create({ data: { actorId: admin.id, action: 'user.roles', target: id, meta: dto as object } });
    return this.prisma.userRole.findMany({ where: { userId: id }, select: { role: true } });
  }

  @Get('users')
  users(@Query('q') q?: string, @Query('role') role?: Role) {
    return this.prisma.user.findMany({
      where: {
        ...(q ? { OR: [{ name: { contains: q, mode: 'insensitive' } }, { email: { contains: q } }, { phone: { contains: q } }] } : {}),
        ...(role ? { roles: { some: { role } } } : {}),
      },
      take: 100,
      orderBy: { createdAt: 'desc' },
      select: { id: true, name: true, email: true, phone: true, status: true, createdAt: true, roles: { select: { role: true } }, teacherProfile: { select: { verifiedAt: true } } },
    });
  }

  @Patch('users/:id/status')
  async setStatus(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() admin: AuthUser, @Body() dto: StatusDto) {
    if (id === admin.id) throw new ForbiddenException('You cannot block yourself');
    const user = await this.prisma.user.update({ where: { id }, data: { status: dto.status }, select: { id: true, status: true } });
    if (dto.status === 'BLOCKED') await this.prisma.refreshToken.updateMany({ where: { userId: id, revokedAt: null }, data: { revokedAt: new Date() } });
    await this.prisma.auditLog.create({ data: { actorId: admin.id, action: `user.${dto.status.toLowerCase()}`, target: id } });
    return user;
  }
}

@Module({ controllers: [AdminController] })
export class AdminModule {}
