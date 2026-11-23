import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AuthUser } from '../common/auth.decorators';
import { PrismaService } from '../prisma/prisma.service';
import { CourseQueryDto, CreateCourseDto, LessonDto, ReviewCourseDto, SectionDto, UpdateCourseDto, UpdateLessonDto } from './courses.dto';
import { MediaService } from './media.service';
import { score } from './ranking';

const EDITABLE = ['DRAFT', 'REJECTED', 'PUBLISHED'];
const lessonPublic = { id: true, title: true, type: true, durationSec: true, isPreview: true, position: true } as const;

@Injectable()
export class CoursesService {
  constructor(
    private prisma: PrismaService,
    private media: MediaService,
  ) {}

  // ---------- teacher ----------

  create(teacherId: string, dto: CreateCourseDto) {
    const { priceBdt, ...rest } = dto;
    return this.prisma.course.create({
      data: { ...rest, teacherId, pricePaisa: priceBdt * 100, isFree: priceBdt === 0 },
    });
  }

  /** Loads a course and checks the caller owns it (admins may manage any course). */
  async owned(courseId: string, user: AuthUser) {
    const course = await this.prisma.course.findUnique({ where: { id: courseId } });
    if (!course) throw new NotFoundException('Course not found');
    if (course.teacherId !== user.id && !user.roles.includes('ADMIN')) throw new ForbiddenException();
    return course;
  }

  async update(courseId: string, user: AuthUser, dto: UpdateCourseDto) {
    const course = await this.owned(courseId, user);
    if (!EDITABLE.includes(course.status)) throw new ConflictException('Course is under review');
    const { priceBdt, ...rest } = dto;
    const data: Prisma.CourseUpdateInput = { ...rest };
    if (priceBdt !== undefined) Object.assign(data, { pricePaisa: priceBdt * 100, isFree: priceBdt === 0 });
    return this.prisma.course.update({ where: { id: courseId }, data });
  }

  mine(teacherId: string) {
    return this.prisma.course.findMany({
      where: { teacherId },
      orderBy: { updatedAt: 'desc' },
      include: { _count: { select: { enrollments: true } } },
    });
  }

  async curriculumForOwner(courseId: string, user: AuthUser) {
    await this.owned(courseId, user);
    return this.prisma.course.findUnique({
      where: { id: courseId },
      include: { sections: { orderBy: { position: 'asc' }, include: { lessons: { orderBy: { position: 'asc' } } } } },
    });
  }

  async addSection(courseId: string, user: AuthUser, dto: SectionDto) {
    await this.owned(courseId, user);
    const position = dto.position ?? (await this.prisma.section.count({ where: { courseId } }));
    return this.prisma.section.create({ data: { courseId, title: dto.title, position } });
  }

  async updateSection(sectionId: string, user: AuthUser, dto: SectionDto) {
    const section = await this.prisma.section.findUnique({ where: { id: sectionId } });
    if (!section) throw new NotFoundException();
    await this.owned(section.courseId, user);
    return this.prisma.section.update({ where: { id: sectionId }, data: dto });
  }

  async deleteSection(sectionId: string, user: AuthUser) {
    const section = await this.prisma.section.findUnique({ where: { id: sectionId } });
    if (!section) throw new NotFoundException();
    await this.owned(section.courseId, user);
    await this.prisma.section.delete({ where: { id: sectionId } });
  }

  async addLesson(sectionId: string, user: AuthUser, dto: LessonDto) {
    const section = await this.prisma.section.findUnique({ where: { id: sectionId } });
    if (!section) throw new NotFoundException();
    await this.owned(section.courseId, user);
    const position = dto.position ?? (await this.prisma.lesson.count({ where: { sectionId } }));
    return this.prisma.lesson.create({ data: { ...dto, sectionId, position } });
  }

  private async ownedLesson(lessonId: string, user: AuthUser) {
    const lesson = await this.prisma.lesson.findUnique({ where: { id: lessonId }, include: { section: true } });
    if (!lesson) throw new NotFoundException();
    await this.owned(lesson.section.courseId, user);
    return lesson;
  }

  async updateLesson(lessonId: string, user: AuthUser, dto: UpdateLessonDto) {
    await this.ownedLesson(lessonId, user);
    return this.prisma.lesson.update({ where: { id: lessonId }, data: dto });
  }

  async deleteLesson(lessonId: string, user: AuthUser) {
    await this.ownedLesson(lessonId, user);
    await this.prisma.lesson.delete({ where: { id: lessonId } });
  }

  /**
   * A course needs at least one lesson before it can go to review.
   * The admin's own (official Tech.Dropout) courses skip review and publish at once.
   */
  async submitForReview(courseId: string, user: AuthUser) {
    const course = await this.owned(courseId, user);
    if (course.status === 'IN_REVIEW') throw new ConflictException('Already in review');
    const lessons = await this.prisma.lesson.count({ where: { section: { courseId } } });
    if (lessons === 0) throw new BadRequestException('Add at least one lesson before submitting');
    if (user.roles.includes('ADMIN') && course.teacherId === user.id) {
      return this.prisma.course.update({
        where: { id: courseId },
        data: { status: 'PUBLISHED', adminNote: null, publishedAt: course.publishedAt ?? new Date() },
      });
    }
    return this.prisma.course.update({ where: { id: courseId }, data: { status: 'IN_REVIEW', adminNote: null } });
  }

  // ---------- admin ----------

  reviewQueue() {
    return this.prisma.course.findMany({
      where: { status: 'IN_REVIEW' },
      orderBy: { updatedAt: 'asc' },
      include: { teacher: { select: { id: true, name: true } }, _count: { select: { sections: true } } },
    });
  }

  async review(courseId: string, adminId: string, dto: ReviewCourseDto) {
    const course = await this.prisma.course.findUnique({ where: { id: courseId } });
    if (!course) throw new NotFoundException();
    if (course.status !== 'IN_REVIEW') throw new ConflictException('Course is not in review');
    if (dto.decision === 'REJECTED' && !dto.note) throw new BadRequestException('A note is required when rejecting');
    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.course.update({
        where: { id: courseId },
        data: {
          status: dto.decision,
          adminNote: dto.note,
          publishedAt: dto.decision === 'PUBLISHED' ? (course.publishedAt ?? new Date()) : course.publishedAt,
        },
      });
      await tx.notification.create({
        data: {
          userId: course.teacherId,
          title: 'Course review',
          body: dto.decision === 'PUBLISHED' ? `"${course.title}" is now live.` : `"${course.title}" needs changes.`,
        },
      });
      await tx.auditLog.create({ data: { actorId: adminId, action: `course.${dto.decision.toLowerCase()}`, target: courseId } });
      return updated;
    });
  }

  setFeatured(courseId: string, isFeatured: boolean) {
    return this.prisma.course.update({ where: { id: courseId }, data: { isFeatured } });
  }

  // ---------- public ----------

  async search(query: CourseQueryDto) {
    const page = query.page ?? 1;
    const pageSize = query.pageSize ?? 20;
    const where: Prisma.CourseWhereInput = { status: 'PUBLISHED' };
    if (query.q) {
      where.OR = [
        { title: { contains: query.q, mode: 'insensitive' } },
        { subtitle: { contains: query.q, mode: 'insensitive' } },
        { description: { contains: query.q, mode: 'insensitive' } },
      ];
    }
    if (query.category) where.category = { slug: query.category };
    if (query.free) where.isFree = query.free === 'true';
    if (query.level) where.level = query.level;

    const select = {
      id: true, title: true, subtitle: true, thumbnailUrl: true, pricePaisa: true, isFree: true, level: true,
      language: true, ratingAvg: true, ratingCount: true, isFeatured: true, publishedAt: true,
      teacher: { select: { id: true, name: true } },
      category: { select: { name: true, slug: true } },
    } as const;

    const sort = query.sort ?? 'relevance';
    if (sort !== 'relevance') {
      const orderBy: Prisma.CourseOrderByWithRelationInput = {
        newest: { publishedAt: 'desc' as const },
        rating: { ratingAvg: 'desc' as const },
        price_asc: { pricePaisa: 'asc' as const },
        price_desc: { pricePaisa: 'desc' as const },
      }[sort]!;
      const [total, items] = await Promise.all([
        this.prisma.course.count({ where }),
        this.prisma.course.findMany({ where, select, orderBy, skip: (page - 1) * pageSize, take: pageSize }),
      ]);
      return { total, page, pageSize, items };
    }

    // Relevance: rank the candidate set in memory (fine up to a few thousand courses;
    // move to Postgres full-text search when the catalogue outgrows that).
    const candidates = await this.prisma.course.findMany({ where, select, take: 2000 });
    const since = new Date(Date.now() - 30 * 864e5);
    const recent = await this.prisma.enrollment.groupBy({
      by: ['courseId'],
      where: { courseId: { in: candidates.map((c) => c.id) }, createdAt: { gte: since } },
      _count: { _all: true },
    });
    const recentMap = new Map(recent.map((r) => [r.courseId, r._count._all]));
    const ranked = candidates
      .map((c) => ({ c, s: score({ ...c, recentEnrollments: recentMap.get(c.id) ?? 0 }, query.q) + (c.isFeatured ? 0.05 : 0) }))
      .sort((a, b) => b.s - a.s)
      .map((x) => x.c);
    return { total: ranked.length, page, pageSize, items: ranked.slice((page - 1) * pageSize, page * pageSize) };
  }

  async detail(courseId: string, viewer?: AuthUser) {
    const course = await this.prisma.course.findUnique({
      where: { id: courseId },
      include: {
        teacher: { select: { id: true, name: true, avatarUrl: true, teacherProfile: { select: { headline: true } } } },
        category: { select: { name: true, slug: true } },
        sections: { orderBy: { position: 'asc' }, include: { lessons: { orderBy: { position: 'asc' }, select: lessonPublic } } },
        _count: { select: { enrollments: true } },
      },
    });
    const canSeeUnpublished = viewer && (viewer.id === course?.teacherId || viewer.roles.includes('ADMIN'));
    if (!course || (course.status !== 'PUBLISHED' && !canSeeUnpublished)) throw new NotFoundException('Course not found');
    const enrolled = viewer
      ? !!(await this.prisma.enrollment.findFirst({ where: { userId: viewer.id, courseId, status: 'ACTIVE' } }))
      : false;
    const { adminNote, ...rest } = course;
    return { ...rest, ...(canSeeUnpublished ? { adminNote } : {}), enrolled };
  }

  /**
   * Access rule for a lesson (plan doc, algorithm A):
   * preview lessons are open; otherwise the viewer must be enrolled, the owner, or an admin.
   * Media is returned as a short-lived signed URL, never the raw key.
   */
  async lessonContent(lessonId: string, viewer?: AuthUser) {
    const lesson = await this.prisma.lesson.findUnique({ where: { id: lessonId }, include: { section: { include: { course: true } } } });
    if (!lesson) throw new NotFoundException();
    const course = lesson.section.course;
    let allowed = lesson.isPreview && course.status === 'PUBLISHED';
    if (!allowed && viewer) {
      allowed =
        viewer.id === course.teacherId ||
        viewer.roles.includes('ADMIN') ||
        !!(await this.prisma.enrollment.findFirst({ where: { userId: viewer.id, courseId: course.id, status: 'ACTIVE' } }));
    }
    if (!allowed) throw new ForbiddenException('Enroll in this course to watch this lesson');
    const { mediaKey, section, ...rest } = lesson;
    return { ...rest, courseId: course.id, mediaUrl: mediaKey ? this.media.sign(mediaKey) : null };
  }
}
