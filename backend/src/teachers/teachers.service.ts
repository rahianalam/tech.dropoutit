import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { ApplicationStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ApplyDto, ReviewApplicationDto } from './teachers.dto';

const REAPPLY_AFTER_DAYS = 30;

@Injectable()
export class TeachersService {
  constructor(private prisma: PrismaService) {}

  latestApplication(userId: string) {
    return this.prisma.teacherApplication.findFirst({ where: { userId }, orderBy: { createdAt: 'desc' } });
  }

  /**
   * Submit or resubmit a teacher application.
   * - one open (PENDING) application at a time
   * - CHANGES_REQUESTED: the same application is updated and goes back to PENDING
   * - REJECTED: a new application is allowed after REAPPLY_AFTER_DAYS
   */
  async apply(userId: string, roles: string[], dto: ApplyDto) {
    if (roles.includes('TEACHER')) throw new ConflictException('You are already a teacher');
    const last = await this.latestApplication(userId);
    if (last?.status === 'PENDING') throw new ConflictException('Your application is already under review');
    if (last?.status === 'REJECTED' && last.reviewedAt) {
      const allowedAt = new Date(last.reviewedAt.getTime() + REAPPLY_AFTER_DAYS * 864e5);
      if (allowedAt > new Date()) {
        throw new BadRequestException(`You can apply again after ${allowedAt.toISOString().slice(0, 10)}`);
      }
    }

    const fields = {
      headline: dto.headline,
      bio: dto.bio,
      skills: dto.skills.map((s) => s.trim()).filter(Boolean),
      experience: dto.experience,
      demoVideoUrl: dto.demoVideoUrl,
      status: ApplicationStatus.PENDING,
    };

    return this.prisma.$transaction(async (tx) => {
      // The portfolio is replaced by what was submitted (CVs belong to the jobs side and are kept).
      await tx.portfolioItem.deleteMany({ where: { ownerId: userId, type: { not: 'CV' } } });
      await tx.portfolioItem.createMany({ data: dto.portfolio.map((p) => ({ ...p, ownerId: userId })) });
      return last?.status === 'CHANGES_REQUESTED'
        ? tx.teacherApplication.update({ where: { id: last.id }, data: fields })
        : tx.teacherApplication.create({ data: { ...fields, userId } });
    });
  }

  listApplications(status?: ApplicationStatus) {
    return this.prisma.teacherApplication.findMany({
      where: status ? { status } : {},
      orderBy: { createdAt: 'asc' },
      include: { user: { select: { id: true, name: true, email: true, phone: true, avatarUrl: true } } },
    });
  }

  async getApplication(id: string) {
    const app = await this.prisma.teacherApplication.findUnique({
      where: { id },
      include: { user: { select: { id: true, name: true, email: true, phone: true, avatarUrl: true, portfolioItems: true } } },
    });
    if (!app) throw new NotFoundException();
    return app;
  }

  /** Approving grants the TEACHER role and creates the public teacher profile in one transaction. */
  async review(id: string, adminId: string, dto: ReviewApplicationDto) {
    const app = await this.prisma.teacherApplication.findUnique({ where: { id } });
    if (!app) throw new NotFoundException();
    if (app.status !== 'PENDING') throw new ConflictException(`Application is ${app.status}, not PENDING`);
    if (dto.decision !== 'APPROVED' && !dto.note) {
      throw new BadRequestException('A note is required when requesting changes or rejecting');
    }

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.teacherApplication.update({
        where: { id },
        data: { status: dto.decision, adminNote: dto.note, reviewedById: adminId, reviewedAt: new Date() },
      });
      if (dto.decision === 'APPROVED') {
        await tx.userRole.upsert({
          where: { userId_role: { userId: app.userId, role: 'TEACHER' } },
          create: { userId: app.userId, role: 'TEACHER' },
          update: {},
        });
        await tx.teacherProfile.upsert({
          where: { userId: app.userId },
          create: { userId: app.userId, headline: app.headline, bio: app.bio, skills: app.skills },
          update: { headline: app.headline, bio: app.bio, skills: app.skills },
        });
      }
      const message = {
        APPROVED: 'Congratulations! You are now a teacher on Tech.Dropout.',
        CHANGES_REQUESTED: 'Your teacher application needs changes.',
        REJECTED: 'Your teacher application was not approved.',
      }[dto.decision];
      await tx.notification.create({ data: { userId: app.userId, title: 'Teacher application', body: message } });
      await tx.auditLog.create({
        data: { actorId: adminId, action: `teacher_application.${dto.decision.toLowerCase()}`, target: id },
      });
      return updated;
    });
  }

  async publicProfile(userId: string) {
    const profile = await this.prisma.teacherProfile.findUnique({
      where: { userId },
      select: {
        headline: true,
        bio: true,
        skills: true,
        user: {
          select: {
            id: true,
            name: true,
            avatarUrl: true,
            portfolioItems: { where: { type: { not: 'CV' } } },
            courses: { where: { status: 'PUBLISHED' }, select: { id: true, title: true, thumbnailUrl: true, pricePaisa: true, isFree: true, ratingAvg: true, ratingCount: true } },
          },
        },
      },
    });
    if (!profile) throw new NotFoundException('Teacher not found');
    return profile;
  }
}
