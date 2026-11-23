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

  /** My courses, most recently studied first, each with the lesson to resume from. */
  async mine(userId: string) {
    const rows = await this.prisma.enrollment.findMany({
      where: { userId, status: 'ACTIVE' },
      include: {
        course: {
          select: {
            id: true, title: true, thumbnailUrl: true, teacher: { select: { name: true } },
            category: { select: { name: true, color: true, icon: true } },
            sections: { orderBy: { position: 'asc' }, select: { lessons: { orderBy: { position: 'asc' }, select: { id: true, title: true } } } },
          },
        },
        progress: { select: { lessonId: true, completed: true, updatedAt: true } },
      },
    });
    const last = (r: (typeof rows)[number]) => Math.max(r.createdAt.getTime(), ...r.progress.map((p) => p.updatedAt.getTime()));
    return rows
      .map((r) => ({ r, at: last(r) }))
      .sort((a, b) => b.at - a.at)
      .map(({ r: { course: { sections, ...course }, progress, ...e }, at }) => {
        const lessons = sections.flatMap((s) => s.lessons);
        const done = new Set(progress.filter((p) => p.completed).map((p) => p.lessonId));
        const next = lessons.find((l) => !done.has(l.id)) ?? lessons[0];
        return { ...e, course, lessonCount: lessons.length, completedCount: done.size, resumeLesson: next ?? null, lastActivityAt: new Date(at) };
      });
  }

  /** Which lessons of a course I've finished (for the player and the curriculum checkmarks). */
  async courseProgress(userId: string, courseId: string) {
    const e = await this.prisma.enrollment.findUnique({
      where: { userId_courseId: { userId, courseId } },
      include: { progress: { select: { lessonId: true, completed: true, watchedSec: true } } },
    });
    if (!e || e.status !== 'ACTIVE') return { enrolled: false, progressPct: 0, lessons: [] };
    return { enrolled: true, progressPct: e.progressPct, lessons: e.progress };
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

  @Get('me/courses/:id/progress')
  courseProgress(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) { return this.enrollments.courseProgress(u.id, id); }

  @Post('lessons/:id/progress')
  progress(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser, @Body() dto: ProgressDto) {
    return this.enrollments.progress(u.id, id, dto);
  }
}

@Module({ controllers: [EnrollmentsController], providers: [EnrollmentsService] })
export class EnrollmentsModule {}
