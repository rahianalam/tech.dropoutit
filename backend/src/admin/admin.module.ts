import { Body, Controller, ForbiddenException, Get, Module, Param, ParseUUIDPipe, Patch, Query } from '@nestjs/common';
import { IsEnum } from 'class-validator';
import { Role, UserStatus } from '@prisma/client';
import { AuthUser, CurrentUser, Roles } from '../common/auth.decorators';
import { PrismaService } from '../prisma/prisma.service';

class StatusDto {
  @IsEnum(UserStatus) status: UserStatus;
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
    return { users, teachers, publishedCourses, enrollments, pendingApplications, coursesInReview, jobsInReview, liveJobs };
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
      select: { id: true, name: true, email: true, phone: true, status: true, createdAt: true, roles: { select: { role: true } } },
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
