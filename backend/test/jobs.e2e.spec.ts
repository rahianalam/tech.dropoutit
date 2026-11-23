import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as bcrypt from 'bcryptjs';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { skillMatch } from '../src/jobs/jobs.service';
import { PrismaService } from '../src/prisma/prisma.service';
import { configureApp } from '../src/setup';

describe('skill match', () => {
  it('counts shared skills ignoring case and spaces', () => {
    expect(skillMatch(['Flutter', 'Dart', 'Firebase'], [' flutter', 'DART', 'Figma'])).toBe(2);
    expect(skillMatch(['Go'], [])).toBe(0);
  });
});

describe('jobs (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let http: ReturnType<typeof request>;
  const api = '/api/v1';
  const t: Record<string, string> = {};
  const auth = (who: string) => ({ Authorization: `Bearer ${t[who]}` });
  const job = {
    title: 'Junior Flutter Developer',
    description: 'আমাদের মোবাইল টিমে একজন জুনিয়র Flutter ডেভেলপার দরকার। Riverpod ও REST API জানা থাকলে ভালো।',
    skills: ['Flutter', 'Dart'],
    type: 'FULL_TIME',
    location: 'ঢাকা',
    salaryMin: 25000,
    salaryMax: 40000,
  };
  let jobId: string;
  let appId: string;

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
    await prisma.user.create({ data: { name: 'Admin', email: 'admin@j.bd', passwordHash: hash, roles: { create: [{ role: 'ADMIN' }] } } });
    for (const n of ['hirer', 'seeker', 'other']) await prisma.user.create({ data: { name: n, email: `${n}@j.bd`, passwordHash: hash, roles: { create: [{ role: 'STUDENT' }] } } });
    for (const who of ['admin', 'hirer', 'seeker', 'other']) {
      t[who] = (await http.post(`${api}/auth/login`).send({ identifier: `${who}@j.bd`, password: 'password123' })).body.accessToken;
    }
  });
  afterAll(async () => app.close());

  it('posting a job needs a company profile, which grants the employer role', async () => {
    await http.post(`${api}/employer/jobs`).set(auth('hirer')).send(job).expect(403);
    await http.put(`${api}/employer/profile`).set(auth('hirer')).send({ companyName: 'Dhaka Apps Ltd', website: 'https://dhakaapps.example', location: 'ঢাকা' }).expect(200);
    const me = await http.get(`${api}/auth/me`).set(auth('hirer')).expect(200);
    expect(me.body.roles).toContain('EMPLOYER');
  });

  it('an unverified company’s job waits for admin review and is hidden until approved', async () => {
    await http.post(`${api}/employer/jobs`).set(auth('hirer')).send({ ...job, salaryMin: 50000 }).expect(400);
    const res = await http.post(`${api}/employer/jobs`).set(auth('hirer')).send(job).expect(201);
    jobId = res.body.id;
    expect(res.body.status).toBe('PENDING');
    expect((await http.get(`${api}/jobs`).expect(200)).body.total).toBe(0);
    await http.get(`${api}/jobs/${jobId}`).expect(404);
    await http.get(`${api}/jobs/${jobId}`).set(auth('hirer')).expect(200);

    const queue = await http.get(`${api}/admin/jobs`).set(auth('admin')).expect(200);
    expect(queue.body.map((j: { id: string }) => j.id)).toEqual([jobId]);
    await http.post(`${api}/admin/jobs/${jobId}/approve`).set(auth('hirer')).expect(403);
    await http.post(`${api}/admin/jobs/${jobId}/approve`).set(auth('admin')).expect(201);
    const list = await http.get(`${api}/jobs?q=flutter`).expect(200);
    expect(list.body.items[0]).toMatchObject({ id: jobId, employer: { companyName: 'Dhaka Apps Ltd' } });
  });

  it('editing an approved job of an unverified company sends it back to review', async () => {
    const res = await http.put(`${api}/employer/jobs/${jobId}`).set(auth('hirer')).send({ ...job, title: 'Junior Flutter Developer (Remote ok)' }).expect(200);
    expect(res.body.status).toBe('PENDING');
    await http.post(`${api}/admin/jobs/${jobId}/approve`).set(auth('admin')).expect(201);
  });

  it('a verified company’s jobs go live at once', async () => {
    const hirer = await prisma.user.findFirstOrThrow({ where: { email: 'hirer@j.bd' } });
    await http.patch(`${api}/admin/employers/${hirer.id}`).set(auth('admin')).send({ verified: true }).expect(200);
    const res = await http.post(`${api}/employer/jobs`).set(auth('hirer')).send({ ...job, title: 'UI/UX Designer', skills: ['Figma'], type: 'PART_TIME' }).expect(201);
    expect(res.body.status).toBe('LIVE');
  });

  it('a seeker needs a profile with a CV; uploads must be real PDFs', async () => {
    await http.post(`${api}/jobs/${jobId}/apply`).set(auth('seeker')).send({}).expect(400);
    await http.post(`${api}/uploads?kind=CV`).set(auth('seeker')).attach('file', Buffer.from('MZ not a pdf'), { filename: 'cv.pdf', contentType: 'application/pdf' }).expect(400);
    const up = await http.post(`${api}/uploads?kind=CV`).set(auth('seeker')).attach('file', Buffer.from('%PDF-1.4\n% test cv\n'), { filename: 'karim-cv.pdf', contentType: 'application/pdf' }).expect(201);
    // someone else's upload can't be attached
    await http.put(`${api}/seeker/profile`).set(auth('other')).send({ headline: 'Dev', skills: ['Go'], cvUploadId: up.body.id }).expect(400);
    const profile = await http.put(`${api}/seeker/profile`).set(auth('seeker')).send({ headline: 'Flutter শিখছি', skills: ['flutter', 'Firebase'], cvUploadId: up.body.id }).expect(200);
    expect(profile.body.cvUrl).toMatch(/^http:\/\/localhost:3000\/api\/v1\/files\/[0-9a-f-]+\?exp=\d+&sig=/);
    const file = await http.get(profile.body.cvUrl.replace(/^https?:\/\/[^/]+/, '')).expect(200); // path incl. /api/v1
    expect(file.headers['content-type']).toBe('application/pdf');
    await http.get(profile.body.cvUrl.replace(/^https?:\/\/[^/]+/, '').replace(/sig=[^&]+/, 'sig=forged')).expect(403);
  });

  it('jobs that match the seeker’s skills come first', async () => {
    const list = await http.get(`${api}/jobs`).set(auth('seeker')).expect(200);
    expect(list.body.items[0]).toMatchObject({ id: jobId, match: 1 });
  });

  it('seeker applies once; employer sees CV and moves the stage; seeker is told', async () => {
    const res = await http.post(`${api}/jobs/${jobId}/apply`).set(auth('seeker')).send({ coverLetter: 'আমি আগ্রহী' }).expect(201);
    appId = res.body.id;
    await http.post(`${api}/jobs/${jobId}/apply`).set(auth('seeker')).send({}).expect(409);
    await http.post(`${api}/jobs/${jobId}/apply`).set(auth('hirer')).send({}).expect(403); // own job
    expect((await http.get(`${api}/jobs/${jobId}`).set(auth('seeker'))).body.applied.stage).toBe('APPLIED');

    await http.get(`${api}/employer/jobs/${jobId}/applications`).set(auth('other')).expect(403);
    const apps = await http.get(`${api}/employer/jobs/${jobId}/applications`).set(auth('hirer')).expect(200);
    expect(apps.body[0]).toMatchObject({ id: appId, match: 1, coverLetter: 'আমি আগ্রহী', seeker: { name: 'seeker', seekerProfile: { headline: 'Flutter শিখছি' } } });
    expect(apps.body[0].cvUrl).toContain('/files/');
    const mine = await http.get(`${api}/employer/jobs`).set(auth('hirer')).expect(200);
    expect(mine.body.find((j: { id: string }) => j.id === jobId)).toMatchObject({ newApplications: 1 });

    await http.patch(`${api}/employer/applications/${appId}`).set(auth('hirer')).send({ stage: 'SHORTLISTED', note: 'ভালো পোর্টফোলিও' }).expect(200);
    const notes = await http.get(`${api}/me/notifications`).set(auth('seeker')).expect(200);
    expect(notes.body[0].title).toContain('শর্টলিস্টেড');
    const my = await http.get(`${api}/me/applications`).set(auth('seeker')).expect(200);
    expect(my.body[0]).toMatchObject({ stage: 'SHORTLISTED', job: { employer: { companyName: 'Dhaka Apps Ltd' } } });
    expect(my.body[0].note).toBeUndefined(); // employer's note stays private
    await http.delete(`${api}/me/applications/${appId}`).set(auth('seeker')).expect(400); // already reviewed
  });

  it('closed or expired jobs stop taking applications', async () => {
    await http.post(`${api}/employer/jobs/${jobId}/close`).set(auth('hirer')).expect(201);
    await http.post(`${api}/jobs/${jobId}/apply`).set(auth('other')).send({}).expect(404);
    const old = await prisma.job.create({ data: { ...job, type: 'FULL_TIME', employerId: (await prisma.employerProfile.findFirstOrThrow()).userId, status: 'LIVE', publishedAt: new Date(), deadline: new Date(Date.now() - 1000) } });
    expect((await http.get(`${api}/jobs`)).body.items.map((j: { id: string }) => j.id)).not.toContain(old.id);
  });
});
