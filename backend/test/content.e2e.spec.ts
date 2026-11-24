import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as bcrypt from 'bcryptjs';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/prisma/prisma.service';
import { configureApp } from '../src/setup';

/** A tiny fake MP4: just enough header for the type check ("ftyp" at byte 4). */
const mp4 = Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from('ftypisom'), Buffer.alloc(1000, 7)]);

describe('course content, video storage, admin tools, account security (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let http: ReturnType<typeof request>;
  const api = '/api/v1';
  const t: Record<string, string> = {};
  const auth = (who: string) => ({ Authorization: `Bearer ${t[who]}` });
  let courseId: string;
  let lessonId: string;

  beforeAll(async () => {
    const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = mod.createNestApplication();
    configureApp(app);
    await app.init();
    prisma = app.get(PrismaService);
    http = request(app.getHttpServer());
    const tables = await prisma.$queryRaw<{ tablename: string }[]>`SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename <> '_prisma_migrations'`;
    await prisma.$executeRawUnsafe(`TRUNCATE ${tables.map((x) => `"${x.tablename}"`).join(',')} CASCADE`);
    const hash = await bcrypt.hash('password123', 10);
    await prisma.user.create({ data: { name: 'Admin', email: 'admin@c.bd', passwordHash: hash, roles: { create: [{ role: 'ADMIN' }] } } });
    for (const n of ['teach', 'other', 'stud']) {
      await prisma.user.create({
        data: { name: n, email: `${n}@c.bd`, passwordHash: hash, roles: { create: [{ role: n === 'stud' ? 'STUDENT' : 'TEACHER' }] }, ...(n === 'stud' ? {} : { teacherProfile: { create: { headline: 'T', bio: 'B', skills: [], canSellPaid: true } } }) },
      });
    }
    for (const who of ['admin', 'teach', 'other', 'stud']) {
      t[who] = (await http.post(`${api}/auth/login`).send({ identifier: `${who}@c.bd`, password: 'password123' })).body.accessToken;
    }
  });
  afterAll(async () => app.close());

  it('saves learning outcomes, requirements and a "was" price', async () => {
    const res = await http.post(`${api}/teacher/courses`).set(auth('teach')).send({
      title: 'Flutter basics', description: 'A long enough description for the course.', priceBdt: 999, originalPriceBdt: 1999,
      outcomes: ['Build apps', 'Publish to Play Store'], requirements: ['A laptop'], audience: ['Beginners'],
    }).expect(201);
    courseId = res.body.id;
    expect(res.body).toMatchObject({ pricePaisa: 99900, originalPricePaisa: 199900, outcomes: ['Build apps', 'Publish to Play Store'] });
    const section = (await http.post(`${api}/teacher/courses/${courseId}/sections`).set(auth('teach')).send({ title: 'Intro' }).expect(201)).body;
    lessonId = (await http.post(`${api}/teacher/sections/${section.id}/lessons`).set(auth('teach')).send({ title: 'Hello' }).expect(201)).body.id;
  });

  it('a teacher uploads a lesson video; others cannot; uploaded keys cannot be forged', async () => {
    await http.post(`${api}/teacher/lessons/${lessonId}/video`).set(auth('other')).attach('file', mp4, 'a.mp4').expect(403);
    await http.post(`${api}/teacher/lessons/${lessonId}/video`).set(auth('teach')).attach('file', Buffer.from('not a video at all'), 'a.mp4').expect(400);
    const up = await http.post(`${api}/teacher/lessons/${lessonId}/video`).set(auth('teach')).field('durationSec', '95').attach('file', mp4, 'intro.mp4').expect(201);
    expect(up.body).toMatchObject({ hasVideo: true, durationSec: 95 });
    expect(up.body.mediaKey).toBeUndefined();
    await http.patch(`${api}/teacher/lessons/${lessonId}`).set(auth('other')).send({ mediaKey: 'x' }).expect(403);
    await http.patch(`${api}/teacher/lessons/${lessonId}`).set(auth('teach')).send({ mediaKey: `upload:${up.body.video.id}` }).expect(400);
    const cur = (await http.get(`${api}/teacher/courses/${courseId}`).set(auth('teach')).expect(200)).body;
    expect(cur.sections[0].lessons[0]).toMatchObject({ hasVideo: true, videoSource: 'upload' });
  });

  it('streams the video with HTTP Range only to people allowed to watch', async () => {
    await http.get(`${api}/lessons/${lessonId}`).set(auth('stud')).expect(403);
    const owner = (await http.get(`${api}/lessons/${lessonId}`).set(auth('teach')).expect(200)).body;
    const path = new URL(owner.mediaUrl).pathname + new URL(owner.mediaUrl).search;
    const part = await http.get(path).set('Range', 'bytes=0-11').expect(206);
    expect(part.headers['content-range']).toBe(`bytes 0-11/${mp4.length}`);
    expect(Buffer.from(part.body).subarray(4, 8).toString()).toBe('ftyp');
    const full = await http.get(path).expect(200);
    expect(Number(full.headers['content-length'])).toBe(mp4.length);
    await http.get(path.replace(/sig=[^&]+/, 'sig=bad')).expect(403);
  });

  it('admin course manager: lists all, takes down and republishes with a note', async () => {
    await http.get(`${api}/admin/courses`).set(auth('teach')).expect(403);
    const all = (await http.get(`${api}/admin/courses?q=flutter`).set(auth('admin')).expect(200)).body;
    expect(all.map((c: { id: string }) => c.id)).toContain(courseId);
    await http.post(`${api}/admin/courses/${courseId}/status`).set(auth('admin')).send({ status: 'PUBLISHED' }).expect(201);
    await http.get(`${api}/courses/${courseId}`).expect(200);
    await http.post(`${api}/admin/courses/${courseId}/status`).set(auth('admin')).send({ status: 'DRAFT', note: 'Audio is too low' }).expect(201);
    await http.get(`${api}/courses/${courseId}`).expect(404);
    const teacher = await prisma.user.findFirstOrThrow({ where: { email: 'teach@c.bd' } });
    expect(await prisma.notification.count({ where: { userId: teacher.id, body: { contains: 'Audio is too low' } } })).toBe(1);
  });

  it('admin manages categories with icon, colour and order', async () => {
    const cat = (await http.post(`${api}/admin/categories`).set(auth('admin')).send({ name: 'Design', slug: 'design', icon: 'brush', color: '#E07A45' }).expect(201)).body;
    await http.patch(`${api}/admin/categories/${cat.id}`).set(auth('admin')).send({ name: 'UI Design', position: 3 }).expect(200);
    await http.patch(`${api}/teacher/courses/${courseId}`).set(auth('teach')).send({ categoryId: cat.id }).expect(200);
    const list = (await http.get(`${api}/categories`).expect(200)).body;
    expect(list[0]).toMatchObject({ name: 'UI Design', icon: 'brush', position: 3, courseCount: 0 });
    await http.delete(`${api}/admin/categories/${cat.id}`).set(auth('admin')).expect(204);
    expect((await prisma.course.findUniqueOrThrow({ where: { id: courseId } })).categoryId).toBeNull();
  });

  it('admin grants roles and sees a richer dashboard', async () => {
    const stud = await prisma.user.findFirstOrThrow({ where: { email: 'stud@c.bd' } });
    const roles = (await http.patch(`${api}/admin/users/${stud.id}/roles`).set(auth('admin')).send({ add: ['TEACHER'] }).expect(200)).body;
    expect(roles.map((r: { role: string }) => r.role).sort()).toEqual(['STUDENT', 'TEACHER']);
    const admin = await prisma.user.findFirstOrThrow({ where: { email: 'admin@c.bd' } });
    await http.patch(`${api}/admin/users/${admin.id}/roles`).set(auth('admin')).send({ remove: ['ADMIN'] }).expect(403);
    const stats = (await http.get(`${api}/admin/stats`).set(auth('admin')).expect(200)).body;
    expect(stats).toHaveProperty('revenue30Paisa', 0);
  });

  it('the admin changes their login email and password', async () => {
    await http.post(`${api}/auth/change-login`).set(auth('admin')).send({ password: 'wrong', email: 'boss@c.bd' }).expect(401);
    await http.post(`${api}/auth/change-login`).set(auth('admin')).send({ password: 'password123', email: 'teach@c.bd' }).expect(409);
    const me = (await http.post(`${api}/auth/change-login`).set(auth('admin')).send({ password: 'password123', email: 'Boss@c.bd' }).expect(200)).body;
    expect(me.email).toBe('boss@c.bd');
    const old = (await http.post(`${api}/auth/login`).send({ identifier: 'boss@c.bd', password: 'password123' }).expect(200)).body;
    await http.post(`${api}/auth/change-password`).set(auth('admin')).send({ currentPassword: 'nope', newPassword: 'newpass123' }).expect(401);
    const fresh = (await http.post(`${api}/auth/change-password`).set(auth('admin')).send({ currentPassword: 'password123', newPassword: 'newpass123' }).expect(200)).body;
    expect(fresh.refreshToken).toBeTruthy();
    await http.post(`${api}/auth/refresh`).send({ refreshToken: old.refreshToken }).expect(401); // other devices signed out
    await http.post(`${api}/auth/login`).send({ identifier: 'boss@c.bd', password: 'password123' }).expect(401);
    await http.post(`${api}/auth/login`).send({ identifier: 'boss@c.bd', password: 'newpass123' }).expect(200);
  });

  it('deleting a lesson removes its uploaded video', async () => {
    const before = await prisma.upload.count({ where: { kind: 'VIDEO' } });
    await http.delete(`${api}/teacher/lessons/${lessonId}`).set(auth('teach')).expect(204);
    expect(await prisma.upload.count({ where: { kind: 'VIDEO' } })).toBe(before - 1);
  });
});
