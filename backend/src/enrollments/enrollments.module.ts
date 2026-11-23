import { Body, Controller, Get, HttpException, HttpStatus, Injectable, Module, NotFoundException, Param, ParseUUIDPipe, Post, ForbiddenException } from '@nestjs/common';
import { IsBoolean, IsInt, IsOptional, Min } from 'class-validator';
import { AuthUser, CurrentUser } from '../common/auth.decorators';
import { PrismaService } from '../prisma/prisma.service';

class ProgressDto {
  @IsInt() @Min(0) watchedSec: number;
  @IsOptional() @IsBoolean() completed?: boolean;
}

@Injectable()
export class EnrollmentsService {
  constructor(private prisma: PrismaService) {}

  /**
   * Free courses enroll at once. Paid courses answer 402 with the price so the
   * app can start checkout (payments arrive in phase 2 and create the enrollment
   * only after the gateway payment is verified on the server).
   */
  async enroll(userId: string, courseId: string) {
    const course = await this.prisma.course.findUnique({ where: { id: courseId } });
    if (!course || course.status !== 'PUBLISHED') throw new NotFoundException('Course not found');
    if (course.teacherId === userId) throw new ForbiddenException('You cannot enroll in your own course');
    const existing = await this.prisma.enrollment.findUnique({ where: { userId_courseId: { userId, courseId } } });
    if (existing?.status === 'ACTIVE') return existing;
    if (!course.isFree) {
      throw new HttpException(
        { statusCode: 402, message: 'Payment required', pricePaisa: course.pricePaisa, courseId },
        HttpStatus.PAYMENT_REQUIRED,
      );
    }
    return this.prisma.enrollment.upsert({
      where: { userId_courseId: { userId, courseId } },
      create: { userId, courseId },
      update: { status: 'ACTIVE' },
    });
  }

  mine(userId: string) {
    return this.prisma.enrollment.findMany({
      where: { userId, status: 'ACTIVE' },
      orderBy: { createdAt: 'desc' },
      include: { course: { select: { id: true, title: true, thumbnailUrl: true, teacher: { select: { name: true } } } } },
    });
  }

  /** Saves lesson progress and recomputes the course percentage. 90% watched counts as complete. */
  async progress(userId: string, lessonId: string, dto: ProgressDto) {
    const lesson = await this.prisma.lesson.findUnique({ where: { id: lessonId }, include: { section: true } });
    if (!lesson) throw new NotFoundException();
    const enrollment = await this.prisma.enrollment.findUnique({
      where: { userId_courseId: { userId, courseId: lesson.section.courseId } },
    });
    if (!enrollment || enrollment.status !== 'ACTIVE') throw new ForbiddenException('Not enrolled');

    const completed = dto.completed ?? (lesson.durationSec > 0 && dto.watchedSec >= lesson.durationSec * 0.9);
    await this.prisma.lessonProgress.upsert({
      where: { enrollmentId_lessonId: { enrollmentId: enrollment.id, lessonId } },
      create: { enrollmentId: enrollment.id, lessonId, watchedSec: dto.watchedSec, completed },
      update: { watchedSec: dto.watchedSec, ...(completed ? { completed: true } : {}) },
    });

    const [total, done] = await Promise.all([
      this.prisma.lesson.count({ where: { section: { courseId: lesson.section.courseId } } }),
      this.prisma.lessonProgress.count({ where: { enrollmentId: enrollment.id, completed: true } }),
    ]);
    const progressPct = total ? Math.round((done / total) * 100) : 0;
    return this.prisma.enrollment.update({
      where: { id: enrollment.id },
      data: { progressPct, completedAt: progressPct === 100 ? (enrollment.completedAt ?? new Date()) : null },
    });
  }
}

@Controller()
export class EnrollmentsController {
  constructor(private enrollments: EnrollmentsService) {}

  @Post('courses/:id/enroll')
  enroll(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) { return this.enrollments.enroll(u.id, id); }

  @Get('me/enrollments')
  mine(@CurrentUser() u: AuthUser) { return this.enrollments.mine(u.id); }

  @Post('lessons/:id/progress')
  progress(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser, @Body() dto: ProgressDto) {
    return this.enrollments.progress(u.id, id, dto);
  }
}

@Module({ controllers: [EnrollmentsController], providers: [EnrollmentsService] })
export class EnrollmentsModule {}
