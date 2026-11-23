import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as bcrypt from 'bcryptjs';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/prisma/prisma.service';
import { configureApp } from '../src/setup';

/**
 * Walks the phase-1 flow end to end against a real Postgres:
 * register → apply as teacher → admin approves → course built → admin publishes
 * → student finds it, enrolls (free) or gets 402 (paid) → watches lessons → progress.
 */
describe('Tech.Dropout API (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let http: ReturnType<typeof request>;
  const api = '/api/v1';
  const tokens: Record<string, string> = {};

  const auth = (who: string) => ({ Authorization: `Bearer ${tokens[who]}` });

  beforeAll(async () => {
    const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = mod.createNestApplication();
    configureApp(app);
    await app.init();
    prisma = app.get(PrismaService);
    http = request(app.getHttpServer());

    // clean slate
    const tables = await prisma.$queryRaw<{ tablename: string }[]>`SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename <> '_prisma_migrations'`;
    await prisma.$executeRawUnsafe(`TRUNCATE ${tables.map((t) => `"${t.tablename}"`).join(',')} CASCADE`);

    const admin = await prisma.user.create({
      data: { name: 'Admin', email: 'admin@test.bd', passwordHash: await bcrypt.hash('adminpass1', 10), roles: { create: [{ role: 'ADMIN' }] } },
    });
    expect(admin.id).toBeDefined();
    const login = await http.post(`${api}/auth/login`).send({ identifier: 'admin@test.bd', password: 'adminpass1' }).expect(200);
    tokens.admin = login.body.accessToken;
  });

  afterAll(async () => app.close());

  it('health check is public', () => http.get('/health').expect(200, { ok: true }));

  it('registers a teacher-to-be by email and a student by phone', async () => {
    const t = await http.post(`${api}/auth/register`).send({ name: 'Rina Teacher', email: 'rina@test.bd', password: 'password123' }).expect(201);
    tokens.teacher = t.body.accessToken;
    const s = await http.post(`${api}/auth/register`).send({ name: 'Sami Student', phone: '01712345678', password: 'password123' }).expect(201);
    tokens.student = s.body.accessToken;

    await http.post(`${api}/auth/register`).send({ name: 'Dup', phone: '+8801712345678', password: 'password123' }).expect(409);
    await http.post(`${api}/auth/register`).send({ name: 'Bad', phone: '12345', password: 'password123' }).expect(400);

    const login = await http.post(`${api}/auth/login`).send({ identifier: '+8801712345678', password: 'password123' }).expect(200);
    expect(login.body.refreshToken).toContain('.');
    const me = await http.get(`${api}/auth/me`).set(auth('student')).expect(200);
    expect(me.body.roles).toEqual(expect.arrayContaining(['STUDENT', 'JOB_SEEKER']));
  });

  it('rotates refresh tokens and rejects reuse', async () => {
    const login = await http.post(`${api}/auth/login`).send({ identifier: 'rina@test.bd', password: 'password123' }).expect(200);
    const r1 = await http.post(`${api}/auth/refresh`).send({ refreshToken: login.body.refreshToken }).expect(200);
    expect(r1.body.accessToken).toBeDefined();
    await http.post(`${api}/auth/refresh`).send({ refreshToken: login.body.refreshToken }).expect(401);
  });

  it('blocks non-teachers from teacher routes and non-admins from admin routes', async () => {
    await http.post(`${api}/teacher/courses`).set(auth('teacher')).send({}).expect(403);
    await http.get(`${api}/admin/stats`).set(auth('student')).expect(403);
    await http.get(`${api}/admin/stats`).expect(401);
  });

  let applicationId: string;
  const application = {
    headline: 'Flutter developer, 5 years',
    bio: 'I build mobile apps with Flutter and teach beginners how to ship their first app.',
    skills: ['Flutter', 'Dart'],
    experience: '5 years at a software company in Dhaka',
    portfolio: [{ type: 'LINK', title: 'GitHub', url: 'https://github.com/example' }],
  };

  it('teacher applies; admin requests changes; teacher resubmits; admin approves', async () => {
    const a = await http.post(`${api}/teacher-applications`).set(auth('teacher')).send(application).expect(201);
    applicationId = a.body.id;
    expect(a.body.status).toBe('PENDING');
    await http.post(`${api}/teacher-applications`).set(auth('teacher')).send(application).expect(409);

    await http.post(`${api}/admin/teacher-applications/${applicationId}/review`).set(auth('admin')).send({ decision: 'REJECTED' }).expect(400);
    await http.post(`${api}/admin/teacher-applications/${applicationId}/review`).set(auth('admin'))
      .send({ decision: 'CHANGES_REQUESTED', note: 'Please add a demo video' }).expect(201);

    const again = await http.post(`${api}/teacher-applications`).set(auth('teacher'))
      .send({ ...application, demoVideoUrl: 'https://youtu.be/demo' }).expect(201);
    expect(again.body.id).toBe(applicationId);
    expect(again.body.status).toBe('PENDING');

    const queue = await http.get(`${api}/admin/teacher-applications?status=PENDING`).set(auth('admin')).expect(200);
    expect(queue.body).toHaveLength(1);

    await http.post(`${api}/admin/teacher-applications/${applicationId}/review`).set(auth('admin')).send({ decision: 'APPROVED' }).expect(201);
    const me = await http.get(`${api}/auth/me`).set(auth('teacher')).expect(200);
    expect(me.body.roles).toContain('TEACHER');

    const notes = await http.get(`${api}/me/notifications`).set(auth('teacher')).expect(200);
    expect(notes.body[0].body).toMatch(/now a teacher/);
  });

  let freeCourseId: string;
  let paidCourseId: string;
  let previewLessonId: string;
  let lockedLessonId: string;

  it('teacher builds a free and a paid course and submits them', async () => {
    const free = await http.post(`${api}/teacher/courses`).set(auth('teacher'))
      .send({ title: 'Flutter for beginners', description: 'Build your first Flutter app step by step.', priceBdt: 0 }).expect(201);
    freeCourseId = free.body.id;
    expect(free.body.isFree).toBe(true);

    await http.post(`${api}/teacher/courses/${freeCourseId}/submit`).set(auth('teacher')).expect(400); // no lessons yet

    const section = await http.post(`${api}/teacher/courses/${freeCourseId}/sections`).set(auth('teacher')).send({ title: 'Getting started' }).expect(201);
    const l1 = await http.post(`${api}/teacher/sections/${section.body.id}/lessons`).set(auth('teacher'))
      .send({ title: 'Install Flutter', mediaKey: 'videos/install.m3u8', durationSec: 300, isPreview: true }).expect(201);
    const l2 = await http.post(`${api}/teacher/sections/${section.body.id}/lessons`).set(auth('teacher'))
      .send({ title: 'First widget', mediaKey: 'videos/widget.m3u8', durationSec: 600 }).expect(201);
    previewLessonId = l1.body.id;
    lockedLessonId = l2.body.id;
    expect(l2.body.position).toBe(1);
    await http.post(`${api}/teacher/courses/${freeCourseId}/submit`).set(auth('teacher')).expect(201);

    const paid = await http.post(`${api}/teacher/courses`).set(auth('teacher'))
      .send({ title: 'Advanced Flutter state management', description: 'Riverpod, BLoC and clean architecture.', priceBdt: 1500 }).expect(201);
    paidCourseId = paid.body.id;
    expect(paid.body.pricePaisa).toBe(150000);
    const s2 = await http.post(`${api}/teacher/courses/${paidCourseId}/sections`).set(auth('teacher')).send({ title: 'Riverpod' }).expect(201);
    await http.post(`${api}/teacher/sections/${s2.body.id}/lessons`).set(auth('teacher')).send({ title: 'Providers', durationSec: 900 }).expect(201);
    await http.post(`${api}/teacher/courses/${paidCourseId}/submit`).set(auth('teacher')).expect(201);
  });

  it('unpublished courses are hidden; admin publishes them', async () => {
    await http.get(`${api}/courses/${freeCourseId}`).expect(404);
    const queue = await http.get(`${api}/admin/courses/review-queue`).set(auth('admin')).expect(200);
    expect(queue.body).toHaveLength(2);
    for (const id of [freeCourseId, paidCourseId]) {
      await http.post(`${api}/admin/courses/${id}/review`).set(auth('admin')).send({ decision: 'PUBLISHED' }).expect(201);
    }
    const detail = await http.get(`${api}/courses/${freeCourseId}`).expect(200);
    expect(detail.body.sections[0].lessons[0]).not.toHaveProperty('mediaKey');
  });

  it('search finds courses, filters free/paid and ranks the exact match first', async () => {
    const all = await http.get(`${api}/courses?q=flutter`).expect(200);
    expect(all.body.total).toBe(2);
    expect(all.body.items[0].title).toBe('Flutter for beginners');
    const paid = await http.get(`${api}/courses?free=false`).expect(200);
    expect(paid.body.items.map((c: { id: string }) => c.id)).toEqual([paidCourseId]);
    const cheap = await http.get(`${api}/courses?sort=price_asc`).expect(200);
    expect(cheap.body.items[0].id).toBe(freeCourseId);
  });

  it('preview lessons are open, others need enrollment; media comes as a signed URL', async () => {
    const preview = await http.get(`${api}/lessons/${previewLessonId}`).expect(200);
    expect(preview.body.mediaUrl).toMatch(/\/videos\/install\.m3u8\?token=.+&expires=\d+$/);
    await http.get(`${api}/lessons/${lockedLessonId}`).expect(403);
    await http.get(`${api}/lessons/${lockedLessonId}`).set(auth('student')).expect(403);
  });

  it('student enrolls in the free course, gets 402 for the paid one, and tracks progress', async () => {
    await http.post(`${api}/courses/${freeCourseId}/enroll`).set(auth('student')).expect(201);
    await http.post(`${api}/courses/${freeCourseId}/enroll`).set(auth('student')).expect(201); // idempotent
    const paid = await http.post(`${api}/courses/${paidCourseId}/enroll`).set(auth('student')).expect(402);
    expect(paid.body.pricePaisa).toBe(150000);
    await http.post(`${api}/courses/${freeCourseId}/enroll`).set(auth('teacher')).expect(403);

    await http.get(`${api}/lessons/${lockedLessonId}`).set(auth('student')).expect(200);
    const p1 = await http.post(`${api}/lessons/${previewLessonId}/progress`).set(auth('student')).send({ watchedSec: 280 }).expect(201);
    expect(p1.body.progressPct).toBe(50);
    const p2 = await http.post(`${api}/lessons/${lockedLessonId}/progress`).set(auth('student')).send({ watchedSec: 10, completed: true }).expect(201);
    expect(p2.body.progressPct).toBe(100);
    expect(p2.body.completedAt).not.toBeNull();

    const mine = await http.get(`${api}/me/enrollments`).set(auth('student')).expect(200);
    expect(mine.body).toHaveLength(1);
    const detail = await http.get(`${api}/courses/${freeCourseId}`).set(auth('student')).expect(200);
    expect(detail.body.enrolled).toBe(true);
  });

  it('admin edits payout settings and sees stats', async () => {
    const s = await http.get(`${api}/admin/settings`).set(auth('admin')).expect(200);
    expect(s.body).toMatchObject({ courseCommissionBps: 3000, sessionCommissionBps: 2000, holdDays: 7, payoutSchedule: 'MONTHLY' });
    const u = await http.patch(`${api}/admin/settings`).set(auth('admin')).send({ courseCommissionBps: 2500, payoutSchedule: 'WEEKLY' }).expect(200);
    expect(u.body).toMatchObject({ courseCommissionBps: 2500, payoutSchedule: 'WEEKLY' });
    await http.patch(`${api}/admin/settings`).set(auth('admin')).send({ courseCommissionBps: 99999 }).expect(400);

    const stats = await http.get(`${api}/admin/stats`).set(auth('admin')).expect(200);
    expect(stats.body).toMatchObject({ teachers: 1, publishedCourses: 2, enrollments: 1, pendingApplications: 0 });
  });

  it('a blocked user loses access immediately', async () => {
    const me = await http.get(`${api}/auth/me`).set(auth('student')).expect(200);
    await http.patch(`${api}/admin/users/${me.body.id}/status`).set(auth('admin')).send({ status: 'BLOCKED' }).expect(200);
    await http.get(`${api}/auth/me`).set(auth('student')).expect(401);
    await http.post(`${api}/auth/login`).send({ identifier: '01712345678', password: 'password123' }).expect(401);
  });
});
