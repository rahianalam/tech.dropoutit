import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AuthUser } from '../common/auth.decorators';
import { PrismaService } from '../prisma/prisma.service';
import { AdminCourseQueryDto, CourseQueryDto, CourseStatusDto, CreateCourseDto, LessonDto, ReviewCourseDto, SectionDto, UpdateCourseDto, UpdateLessonDto } from './courses.dto';
import { InstructorService } from '../instructor/instructor.service';
import { UploadsService } from '../uploads/uploads.module';
import { MediaService } from './media.service';
import { score } from './ranking';

const EDITABLE = ['DRAFT', 'REJECTED', 'PUBLISHED'];
const lessonPublic = { id: true, title: true, type: true, durationSec: true, isPreview: true, position: true } as const;

@Injectable()
export class CoursesService {
  constructor(
    private prisma: PrismaService,
    private media: MediaService,
    private uploads: UploadsService,
    private instructor: InstructorService,
  ) {}

  /** BDT fields from the form → paisa columns. */
  private money(dto: { priceBdt?: number; originalPriceBdt?: number | null }) {
    const out: Record<string, unknown> = {};
    if (dto.priceBdt !== undefined) Object.assign(out, { pricePaisa: dto.priceBdt * 100, isFree: dto.priceBdt === 0 });
    if (dto.originalPriceBdt !== undefined) out.originalPricePaisa = dto.originalPriceBdt ? dto.originalPriceBdt * 100 : null;
    return out;
  }

  // ---------- teacher ----------

  async create(teacherId: string, dto: CreateCourseDto) {
    if (dto.priceBdt) await this.instructor.assertCanSellPaid(teacherId);
    const { priceBdt, originalPriceBdt, ...rest } = dto;
    return this.prisma.course.create({
      data: { ...rest, teacherId, ...this.money({ priceBdt, originalPriceBdt }) } as Prisma.CourseUncheckedCreateInput,
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
    if (dto.priceBdt && course.isFree) await this.instructor.assertCanSellPaid(course.teacherId);
    const { priceBdt, originalPriceBdt, ...rest } = dto;
    const data: Prisma.CourseUpdateInput = { ...rest, ...this.money({ priceBdt, originalPriceBdt }) };
    return this.prisma.course.update({ where: { id: courseId }, data });
  }

  mine(teacherId: string) {
    return this.prisma.course.findMany({
      where: { teacherId },
      orderBy: { updatedAt: 'desc' },
      include: { _count: { select: { enrollments: true } }, category: { select: { name: true, color: true, icon: true } } },
    });
  }

  async curriculumForOwner(courseId: string, user: AuthUser) {
    await this.owned(courseId, user);
    const course = await this.prisma.course.findUniqueOrThrow({
      where: { id: courseId },
      include: {
        category: { select: { name: true, color: true, icon: true } },
        sections: { orderBy: { position: 'asc' }, include: { lessons: { orderBy: { position: 'asc' } } } },
      },
    });
    return {
      ...course,
      sections: course.sections.map((s) => ({
        ...s,
        lessons: s.lessons.map(({ mediaKey, ...l }) => ({
          ...l,
          hasVideo: !!mediaKey,
          videoSource: !mediaKey ? null : mediaKey.startsWith('upload:') ? 'upload' : /^https?:/.test(mediaKey) ? 'link' : 'cdn',
          videoLink: mediaKey && /^https?:/.test(mediaKey) ? mediaKey : null,
        })),
      })),
    };
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
    this.checkMediaKey(dto.mediaKey);
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
    const lesson = await this.ownedLesson(lessonId, user);
    this.checkMediaKey(dto.mediaKey);
    const updated = await this.prisma.lesson.update({ where: { id: lessonId }, data: dto });
    // Replacing an uploaded video with a link (or clearing it) frees the old file.
    if (dto.mediaKey !== undefined && dto.mediaKey !== lesson.mediaKey) await this.dropVideo(lesson.mediaKey);
    return updated;
  }

  /** Uploaded videos are attached only through attachVideo, so nobody can point at another teacher's file. */
  private checkMediaKey(key?: string | null) {
    if (key?.startsWith('upload:')) throw new BadRequestException('Upload the video file instead');
  }

  async deleteLesson(lessonId: string, user: AuthUser) {
    const lesson = await this.ownedLesson(lessonId, user);
    await this.prisma.lesson.delete({ where: { id: lessonId } });
    await this.dropVideo(lesson.mediaKey);
  }

  /**
   * Uploads a recorded video for a lesson (course owner or admin). The file goes to the active
   * storage driver and the lesson points at it; a previous uploaded video is deleted.
   */
  async attachVideo(lessonId: string, user: AuthUser, file: Express.Multer.File | undefined, durationSec?: number) {
    let lesson;
    try {
      lesson = await this.ownedLesson(lessonId, user);
      const course = await this.prisma.course.findUniqueOrThrow({ where: { id: lesson.section.courseId } });
      await this.instructor.assertVideoQuota(course.teacherId, !!lesson.mediaKey?.startsWith('upload:'));
    } catch (e) {
      if (file?.path) require('fs').rmSync(file.path, { force: true });
      throw e;
    }
    const up = await this.uploads.saveVideo(user.id, file);
    const updated = await this.prisma.lesson.update({
      where: { id: lessonId },
      data: { mediaKey: `upload:${up.id}`, type: 'VIDEO', ...(durationSec ? { durationSec } : {}) },
    });
    await this.dropVideo(lesson.mediaKey);
    const { mediaKey, ...rest } = updated;
    return { ...rest, hasVideo: true, video: { id: up.id, size: up.size, originalName: up.originalName } };
  }

  async removeVideo(lessonId: string, user: AuthUser) {
    const lesson = await this.ownedLesson(lessonId, user);
    await this.prisma.lesson.update({ where: { id: lessonId }, data: { mediaKey: null } });
    await this.dropVideo(lesson.mediaKey);
  }

  private async dropVideo(mediaKey: string | null) {
    if (mediaKey?.startsWith('upload:')) await this.uploads.remove(mediaKey.slice(7));
  }

  /**
   * Turns a lesson's mediaKey into something a player can open:
   *  - "upload:<id>"   → a video uploaded here (signed link to our storage, Range-capable)
   *  - "https://..."   → an external video (YouTube, Vimeo, any CDN) used as-is
   *  - anything else   → a key on the Bunny CDN, signed with MEDIA_SIGNING_KEY
   */
  mediaUrl(mediaKey: string | null) {
    if (!mediaKey) return null;
    if (mediaKey.startsWith('upload:')) return this.uploads.link(mediaKey.slice(7), 4 * 3600);
    if (/^https?:\/\//.test(mediaKey)) return mediaKey;
    return this.media.sign(mediaKey);
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

  /** Every course on the platform, for the admin's course manager. */
  allCourses(q: AdminCourseQueryDto) {
    return this.prisma.course.findMany({
      where: {
        ...(q.status ? { status: q.status } : {}),
        ...(q.q ? { OR: [{ title: { contains: q.q, mode: 'insensitive' } }, { teacher: { name: { contains: q.q, mode: 'insensitive' } } }] } : {}),
      },
      orderBy: { updatedAt: 'desc' },
      take: 200,
      include: {
        teacher: { select: { id: true, name: true } },
        category: { select: { name: true, color: true, icon: true } },
        _count: { select: { enrollments: true, sections: true } },
      },
    });
  }

  /** Admin puts a course live or takes it down (e.g. a complaint), with a note to the teacher. */
  async setStatus(courseId: string, adminId: string, dto: CourseStatusDto) {
    const course = await this.prisma.course.findUnique({ where: { id: courseId } });
    if (!course) throw new NotFoundException();
    const updated = await this.prisma.course.update({
      where: { id: courseId },
      data: {
        status: dto.status,
        adminNote: dto.note ?? null,
        ...(dto.status === 'PUBLISHED' ? { publishedAt: course.publishedAt ?? new Date() } : { isFeatured: false }),
      },
    });
    if (course.teacherId !== adminId) {
      await this.prisma.notification.create({
        data: {
          userId: course.teacherId,
          title: 'Course status',
          body: dto.status === 'PUBLISHED' ? `"${course.title}" is live.` : `"${course.title}" was taken down${dto.note ? `: ${dto.note}` : '.'}`,
        },
      });
    }
    await this.prisma.auditLog.create({ data: { actorId: adminId, action: `course.set_${dto.status.toLowerCase()}`, target: courseId } });
    return updated;
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
      id: true, title: true, subtitle: true, thumbnailUrl: true, pricePaisa: true, originalPricePaisa: true, isFree: true, level: true,
      language: true, ratingAvg: true, ratingCount: true, isFeatured: true, publishedAt: true,
      teacher: { select: { id: true, name: true } },
      category: { select: { name: true, slug: true, color: true, icon: true } },
      _count: { select: { enrollments: true } },
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
        teacher: { select: { id: true, name: true, avatarUrl: true, teacherProfile: { select: { headline: true, bio: true } } } },
        category: { select: { name: true, slug: true, color: true, icon: true } },
        sections: { orderBy: { position: 'asc' }, include: { lessons: { orderBy: { position: 'asc' }, select: lessonPublic } } },
        _count: { select: { enrollments: true } },
      },
    });
    const canSeeUnpublished = viewer && (viewer.id === course?.teacherId || viewer.roles.includes('ADMIN'));
    if (!course || (course.status !== 'PUBLISHED' && !canSeeUnpublished)) throw new NotFoundException('Course not found');
    const enrolled = viewer
      ? !!(await this.prisma.enrollment.findFirst({ where: { userId: viewer.id, courseId, status: 'ACTIVE', OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }] } }))
      : false;
    // Instructor card: how many live courses and students this teacher has.
    const [teacherCourses, teacherStudents] = await Promise.all([
      this.prisma.course.count({ where: { teacherId: course.teacherId, status: 'PUBLISHED' } }),
      this.prisma.enrollment.count({ where: { course: { teacherId: course.teacherId }, status: 'ACTIVE' } }),
    ]);
    const totalSec = course.sections.reduce((t, s) => t + s.lessons.reduce((a, l) => a + l.durationSec, 0), 0);
    const lessonCount = course.sections.reduce((t, s) => t + s.lessons.length, 0);
    const { adminNote, ...rest } = course;
    return {
      ...rest,
      ...(canSeeUnpublished ? { adminNote } : {}),
      enrolled,
      totalSec,
      lessonCount,
      teacherStats: { courses: teacherCourses, students: teacherStudents },
    };
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
        !!(await this.prisma.enrollment.findFirst({ where: { userId: viewer.id, courseId: course.id, status: 'ACTIVE', OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }] } }));
    }
    if (!allowed) throw new ForbiddenException('Enroll in this course to watch this lesson');
    // A learner opening a lesson counts as a view toward the instructor's blue tick.
    if (viewer?.id !== course.teacherId && !viewer?.roles.includes('ADMIN')) {
      await this.prisma.course.update({ where: { id: course.id }, data: { views: { increment: 1 } } });
    }
    const { mediaKey, section, ...rest } = lesson;
    return { ...rest, courseId: course.id, mediaUrl: this.mediaUrl(mediaKey) };
  }

  // ---------- reviews ----------

  /** Enrolled students rate a course once (editable); the course's average is recomputed. */
  async rateCourse(courseId: string, userId: string, rating: number, comment?: string) {
    const enrolled = await this.prisma.enrollment.findFirst({ where: { userId, courseId, status: 'ACTIVE' } });
    if (!enrolled) throw new ForbiddenException('Enroll in the course to review it');
    const review = await this.prisma.review.upsert({
      where: { userId_courseId: { userId, courseId } },
      create: { userId, courseId, rating, comment },
      update: { rating, comment },
    });
    const agg = await this.prisma.review.aggregate({ where: { courseId }, _avg: { rating: true }, _count: true });
    await this.prisma.course.update({ where: { id: courseId }, data: { ratingAvg: agg._avg.rating ?? 0, ratingCount: agg._count } });
    return review;
  }

  reviews(courseId: string) {
    return this.prisma.review.findMany({
      where: { courseId },
      orderBy: { createdAt: 'desc' },
      take: 50,
      include: { user: { select: { name: true, avatarUrl: true } } },
    });
  }
}
