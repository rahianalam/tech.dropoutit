import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { ApplicationStage, Prisma } from '@prisma/client';
import { AuthUser } from '../common/auth.decorators';
import { PrismaService } from '../prisma/prisma.service';
import { UploadsService } from '../uploads/uploads.module';
import { AdminJobQueryDto, ApplyJobDto, EmployerDto, JobDto, JobQueryDto, SeekerDto, StageDto } from './jobs.dto';

const PAGE = 20;
const STAGE_BN: Record<ApplicationStage, string> = {
  APPLIED: 'আবেদন জমা',
  SHORTLISTED: 'শর্টলিস্টেড',
  INTERVIEW: 'ইন্টারভিউ',
  HIRED: 'নিয়োগ পেয়েছেন',
  REJECTED: 'এবার হয়নি',
};
const employerPublic = { select: { userId: true, companyName: true, website: true, about: true, location: true, verified: true } };

/** How many of the job's skills the seeker has (case-insensitive). */
export function skillMatch(jobSkills: string[], seekerSkills: string[]) {
  const mine = new Set(seekerSkills.map((s) => s.trim().toLowerCase()));
  return jobSkills.filter((s) => mine.has(s.trim().toLowerCase())).length;
}

@Injectable()
export class JobsService {
  constructor(private prisma: PrismaService, private uploads: UploadsService) {}

  // ---------- employer ----------

  employerProfile(userId: string) {
    return this.prisma.employerProfile.findUnique({ where: { userId } });
  }

  /** Creating a company profile is self-serve and grants the EMPLOYER role. */
  async upsertEmployer(userId: string, dto: EmployerDto) {
    const data = { companyName: dto.companyName, website: dto.website ?? null, about: dto.about ?? null, location: dto.location ?? null };
    const [profile] = await this.prisma.$transaction([
      this.prisma.employerProfile.upsert({ where: { userId }, create: { userId, ...data }, update: data }),
      this.prisma.userRole.upsert({ where: { userId_role: { userId, role: 'EMPLOYER' } }, create: { userId, role: 'EMPLOYER' }, update: {} }),
    ]);
    return profile;
  }

  private validRange(dto: JobDto) {
    if (dto.salaryMin != null && dto.salaryMax != null && dto.salaryMin > dto.salaryMax) {
      throw new BadRequestException('Minimum salary is more than maximum');
    }
    if (dto.deadline && new Date(dto.deadline) < new Date()) throw new BadRequestException('Deadline is in the past');
  }

  private jobData(dto: JobDto) {
    return {
      title: dto.title.trim(),
      description: dto.description,
      skills: [...new Set(dto.skills.map((s) => s.trim()).filter(Boolean))],
      type: dto.type,
      location: dto.location ?? null,
      salaryMin: dto.salaryMin ?? null,
      salaryMax: dto.salaryMax ?? null,
      deadline: dto.deadline ? new Date(dto.deadline) : null,
    };
  }

  /** Verified companies go live at once; others wait for an admin. */
  async createJob(u: AuthUser, dto: JobDto) {
    const employer = await this.employerProfile(u.id);
    if (!employer) throw new ForbiddenException('Create a company profile first');
    this.validRange(dto);
    const live = employer.verified;
    const job = await this.prisma.job.create({
      data: { ...this.jobData(dto), employerId: u.id, status: live ? 'LIVE' : 'PENDING', publishedAt: live ? new Date() : null },
    });
    if (!live) await this.notifyAdmins('নতুন জব রিভিউয়ের অপেক্ষায়', `${employer.companyName}: ${job.title}`);
    return job;
  }

  private async ownJob(u: AuthUser, id: string) {
    const job = await this.prisma.job.findUnique({ where: { id }, include: { employer: true } });
    if (!job) throw new NotFoundException();
    if (job.employerId !== u.id) throw new ForbiddenException();
    return job;
  }

  /** Editing an unverified company's job sends it back to review, so nobody can swap in content after approval. */
  async updateJob(u: AuthUser, id: string, dto: JobDto) {
    const job = await this.ownJob(u, id);
    if (job.status === 'CLOSED') throw new BadRequestException('This job is closed');
    this.validRange(dto);
    const review = !job.employer.verified;
    const updated = await this.prisma.job.update({
      where: { id },
      data: { ...this.jobData(dto), ...(review ? { status: 'PENDING', rejectReason: null } : {}) },
    });
    if (review) await this.notifyAdmins('এডিট করা জব রিভিউয়ের অপেক্ষায়', `${job.employer.companyName}: ${updated.title}`);
    return updated;
  }

  async closeJob(u: AuthUser, id: string) {
    await this.ownJob(u, id);
    return this.prisma.job.update({ where: { id }, data: { status: 'CLOSED' } });
  }

  async myJobs(u: AuthUser) {
    const jobs = await this.prisma.job.findMany({
      where: { employerId: u.id },
      orderBy: { createdAt: 'desc' },
      include: { _count: { select: { applications: true } } },
    });
    const fresh = await this.prisma.jobApplication.groupBy({
      by: ['jobId'],
      where: { jobId: { in: jobs.map((j) => j.id) }, stage: 'APPLIED' },
      _count: true,
    });
    const freshBy = new Map(fresh.map((f) => [f.jobId, f._count]));
    return jobs.map((j) => ({ ...j, newApplications: freshBy.get(j.id) ?? 0 }));
  }

  /** Applicants with what a hirer needs to decide: CV, profile, portfolio and courses finished on Tech.Dropout. */
  async applicants(u: AuthUser, jobId: string) {
    const job = await this.ownJob(u, jobId);
    const apps = await this.prisma.jobApplication.findMany({
      where: { jobId },
      orderBy: { createdAt: 'desc' },
      include: {
        seeker: {
          select: {
            id: true, name: true, email: true, phone: true,
            seekerProfile: { select: { headline: true, about: true, skills: true, location: true } },
            portfolioItems: { select: { title: true, url: true, type: true } },
            enrollments: { where: { progressPct: 100 }, select: { course: { select: { id: true, title: true } } } },
          },
        },
      },
    });
    return apps.map((a) => ({
      ...a,
      match: skillMatch(job.skills, a.seeker.seekerProfile?.skills ?? []),
      cvUrl: a.cvUploadId ? this.uploads.link(a.cvUploadId) : a.cvLink,
      seeker: { ...a.seeker, completedCourses: a.seeker.enrollments.map((e) => e.course), enrollments: undefined },
    }));
  }

  async setStage(u: AuthUser, appId: string, dto: StageDto) {
    const app = await this.prisma.jobApplication.findUnique({ where: { id: appId }, include: { job: { include: { employer: true } } } });
    if (!app) throw new NotFoundException();
    if (app.job.employerId !== u.id) throw new ForbiddenException();
    const updated = await this.prisma.jobApplication.update({
      where: { id: appId },
      data: { ...(dto.stage ? { stage: dto.stage } : {}), ...(dto.note !== undefined ? { note: dto.note } : {}) },
    });
    if (dto.stage && dto.stage !== app.stage) {
      await this.prisma.notification.create({
        data: { userId: app.seekerId, title: `${app.job.title}: ${STAGE_BN[dto.stage]}`, body: app.job.employer.companyName },
      });
    }
    return updated;
  }

  // ---------- job seeker ----------

  async seekerProfile(userId: string) {
    const p = await this.prisma.seekerProfile.findUnique({ where: { userId }, include: { cvUpload: { select: { id: true, originalName: true } } } });
    return p ? { ...p, cvUrl: p.cvUploadId ? this.uploads.link(p.cvUploadId) : p.cvLink } : null;
  }

  async upsertSeeker(userId: string, dto: SeekerDto) {
    if (dto.cvUploadId) {
      const up = await this.prisma.upload.findUnique({ where: { id: dto.cvUploadId } });
      if (!up || up.ownerId !== userId || up.kind !== 'CV') throw new BadRequestException('Upload your CV first');
    }
    const data = {
      headline: dto.headline.trim(),
      about: dto.about ?? null,
      skills: [...new Set(dto.skills.map((s) => s.trim()).filter(Boolean))],
      location: dto.location ?? null,
      ...(dto.cvUploadId !== undefined ? { cvUploadId: dto.cvUploadId } : {}),
      ...(dto.cvLink !== undefined ? { cvLink: dto.cvLink || null } : {}),
      ...(dto.openToWork !== undefined ? { openToWork: dto.openToWork } : {}),
    };
    await this.prisma.$transaction([
      this.prisma.seekerProfile.upsert({ where: { userId }, create: { userId, ...data }, update: data }),
      this.prisma.userRole.upsert({ where: { userId_role: { userId, role: 'JOB_SEEKER' } }, create: { userId, role: 'JOB_SEEKER' }, update: {} }),
    ]);
    return this.seekerProfile(userId);
  }

  async apply(u: AuthUser, jobId: string, dto: ApplyJobDto) {
    const job = await this.prisma.job.findUnique({ where: { id: jobId }, include: { employer: true } });
    if (!job || job.status !== 'LIVE') throw new NotFoundException('This job is not open');
    if (job.deadline && job.deadline < new Date()) throw new BadRequestException('The deadline has passed');
    if (job.employerId === u.id) throw new ForbiddenException('You cannot apply to your own job');
    const profile = await this.prisma.seekerProfile.findUnique({ where: { userId: u.id } });
    if (!profile) throw new BadRequestException('Set up your job profile first');
    if (!profile.cvUploadId && !profile.cvLink) throw new BadRequestException('Add your CV first');
    try {
      const app = await this.prisma.jobApplication.create({
        data: { jobId, seekerId: u.id, cvUploadId: profile.cvUploadId, cvLink: profile.cvUploadId ? null : profile.cvLink, coverLetter: dto.coverLetter },
      });
      const me = await this.prisma.user.findUnique({ where: { id: u.id }, select: { name: true } });
      await this.prisma.notification.create({ data: { userId: job.employerId, title: `নতুন আবেদন: ${job.title}`, body: me?.name ?? '' } });
      return app;
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') throw new ConflictException('You already applied');
      throw e;
    }
  }

  myApplications(u: AuthUser) {
    return this.prisma.jobApplication.findMany({
      where: { seekerId: u.id },
      orderBy: { createdAt: 'desc' },
      select: {
        id: true, stage: true, createdAt: true, updatedAt: true,
        job: { select: { id: true, title: true, type: true, status: true, employer: { select: { companyName: true } } } },
      },
    });
  }

  /** Withdrawing is only possible before the employer has acted on it. */
  async withdraw(u: AuthUser, id: string) {
    const app = await this.prisma.jobApplication.findUnique({ where: { id } });
    if (!app || app.seekerId !== u.id) throw new NotFoundException();
    if (app.stage !== 'APPLIED') throw new BadRequestException('The employer has already reviewed this application');
    await this.prisma.jobApplication.delete({ where: { id } });
  }

  // ---------- public ----------

  private openWhere(): Prisma.JobWhereInput {
    return { status: 'LIVE', OR: [{ deadline: null }, { deadline: { gte: new Date() } }] };
  }

  /** Newest first; a signed-in seeker sees jobs that match their skills first. */
  async list(q: JobQueryDto, user?: AuthUser) {
    const where: Prisma.JobWhereInput = {
      AND: [
        this.openWhere(),
        ...(q.type ? [{ type: q.type }] : []),
        ...(q.q
          ? [{ OR: [
              { title: { contains: q.q, mode: 'insensitive' as const } },
              { skills: { has: q.q } },
              { employer: { companyName: { contains: q.q, mode: 'insensitive' as const } } },
            ] }]
          : []),
      ],
    };
    const jobs = await this.prisma.job.findMany({
      where,
      orderBy: { publishedAt: 'desc' },
      take: 200,
      include: { employer: employerPublic },
    });
    const skills = user ? (await this.prisma.seekerProfile.findUnique({ where: { userId: user.id } }))?.skills ?? [] : [];
    const scored = jobs.map((j) => ({ ...j, match: skillMatch(j.skills, skills) }));
    if (skills.length) scored.sort((a, b) => b.match - a.match || +(b.publishedAt ?? 0) - +(a.publishedAt ?? 0));
    const page = q.page ?? 1;
    return { items: scored.slice((page - 1) * PAGE, page * PAGE), total: scored.length, page };
  }

  async detail(id: string, user?: AuthUser) {
    const job = await this.prisma.job.findUnique({ where: { id }, include: { employer: employerPublic, _count: { select: { applications: true } } } });
    const mine = user && (job?.employerId === user.id || user.roles.includes('ADMIN'));
    if (!job || (job.status !== 'LIVE' && !mine)) throw new NotFoundException();
    const applied = user ? await this.prisma.jobApplication.findUnique({ where: { jobId_seekerId: { jobId: id, seekerId: user.id } }, select: { id: true, stage: true } }) : null;
    return { ...job, open: job.status === 'LIVE' && (!job.deadline || job.deadline >= new Date()), applied };
  }

  // ---------- admin ----------

  adminJobs(q: AdminJobQueryDto) {
    return this.prisma.job.findMany({
      where: { status: q.status ?? 'PENDING' },
      orderBy: { updatedAt: 'asc' },
      take: 100,
      include: { employer: employerPublic },
    });
  }

  async approve(admin: AuthUser, id: string) {
    const job = await this.prisma.job.findUnique({ where: { id } });
    if (!job) throw new NotFoundException();
    if (job.status !== 'PENDING') throw new BadRequestException('Only pending jobs can be approved');
    const updated = await this.prisma.job.update({ where: { id }, data: { status: 'LIVE', rejectReason: null, publishedAt: job.publishedAt ?? new Date() } });
    await this.prisma.$transaction([
      this.prisma.notification.create({ data: { userId: job.employerId, title: 'জব লাইভ হয়েছে', body: job.title } }),
      this.prisma.auditLog.create({ data: { actorId: admin.id, action: 'job.approve', target: id } }),
    ]);
    return updated;
  }

  async reject(admin: AuthUser, id: string, reason: string) {
    const job = await this.prisma.job.findUnique({ where: { id } });
    if (!job) throw new NotFoundException();
    if (job.status !== 'PENDING') throw new BadRequestException('Only pending jobs can be rejected');
    const updated = await this.prisma.job.update({ where: { id }, data: { status: 'REJECTED', rejectReason: reason } });
    await this.prisma.$transaction([
      this.prisma.notification.create({ data: { userId: job.employerId, title: 'জব পোস্ট অনুমোদন হয়নি', body: `${job.title}: ${reason}` } }),
      this.prisma.auditLog.create({ data: { actorId: admin.id, action: 'job.reject', target: id } }),
    ]);
    return updated;
  }

  employers() {
    return this.prisma.employerProfile.findMany({
      orderBy: { createdAt: 'desc' },
      take: 200,
      include: { user: { select: { name: true, email: true, phone: true } }, _count: { select: { jobs: true } } },
    });
  }

  async verifyEmployer(admin: AuthUser, userId: string, verified: boolean) {
    const p = await this.prisma.employerProfile.update({ where: { userId }, data: { verified } }).catch(() => {
      throw new NotFoundException();
    });
    await this.prisma.auditLog.create({ data: { actorId: admin.id, action: verified ? 'employer.verify' : 'employer.unverify', target: userId } });
    if (verified) await this.prisma.notification.create({ data: { userId, title: 'কোম্পানি ভেরিফায়েড', body: 'এখন থেকে আপনার জব পোস্ট সরাসরি লাইভ হবে।' } });
    return p;
  }

  /** Jobs past their deadline stop showing as open. */
  closeExpired() {
    return this.prisma.job.updateMany({ where: { status: 'LIVE', deadline: { lt: new Date() } }, data: { status: 'CLOSED' } });
  }

  private async notifyAdmins(title: string, body: string) {
    const admins = await this.prisma.userRole.findMany({ where: { role: 'ADMIN' } });
    await this.prisma.notification.createMany({ data: admins.map((a) => ({ userId: a.userId, title, body })) });
  }
}
