import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as bcrypt from 'bcryptjs';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { tierFor } from '../src/fees/fees';
import { GrowthService } from '../src/growth/growth.module';
import { respondBy } from '../src/payments/payments.service';
import { PrismaService } from '../src/prisma/prisma.service';
import { configureApp } from '../src/setup';

const mp4 = Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from('ftypisom'), Buffer.alloc(1000, 7)]);
const png = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(200, 1)]);

describe('rules', () => {
  it('Silver after 25 sales, Gold after 50', () => {
    const s = { silverSales: 25, goldSales: 50 };
    expect([tierFor(24, s), tierFor(25, s), tierFor(49, s), tierFor(50, s)]).toEqual([null, 'SILVER', 'SILVER', 'GOLD']);
  });
  it('a booking request must be answered within the window and at least an hour before the start', () => {
    const now = Date.UTC(2026, 0, 1);
    expect(respondBy(new Date(now + 72 * 3600_000), 24, now).getTime()).toBe(now + 24 * 3600_000);
    expect(respondBy(new Date(now + 5 * 3600_000), 24, now).getTime()).toBe(now + 4 * 3600_000);
  });
});

/** Instructor rules, fees by tier, booking requests, storage plans, referrals and affiliates. */
describe('instructor rules, referrals and affiliates (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let http: ReturnType<typeof request>;
  const api = '/api/v1';
  const t: Record<string, string> = {};
  const id: Record<string, string> = {};
  const auth = (who: string) => ({ Authorization: `Bearer ${t[who]}` });
  const pay = (tranId: string, amount: number) => http.post(`${api}/payments/sslcommerz/ipn`).type('form').send({ val_id: `ok:${tranId}:${amount}` }).expect(200);

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
    const make = async (who: string, roles: string[], profile?: object) => {
      const u = await prisma.user.create({
        data: { name: who, email: `${who}@r.bd`, passwordHash: hash, roles: { create: roles.map((role) => ({ role: role as 'STUDENT' })) }, ...(profile ? { teacherProfile: { create: { headline: 'H', bio: 'B', skills: [], ...profile } } } : {}) },
      });
      id[who] = u.id;
      t[who] = (await http.post(`${api}/auth/login`).send({ identifier: `${who}@r.bd`, password: 'password123' })).body.accessToken;
    };
    await make('admin', ['ADMIN']);
    await make('pro', ['TEACHER'], { canSellPaid: true, hourlyRatePaisa: 60000 });
    await make('newbie', ['TEACHER'], {});
    await make('stud', ['STUDENT']);
    await make('aff', ['STUDENT']);
  });

  afterAll(async () => app.close());

  it('shows the instructor rules before applying, and an application must accept them', async () => {
    const r = (await http.get(`${api}/instructor-rules`).expect(200)).body;
    expect(r).toMatchObject({ sessionCommissionBps: 1000, courseCommissionBps: 700, vatBps: 500, freeCoursesRequired: 10, freeVideoLimit: 10 });
    const app = { headline: 'Designer, 3 years', bio: 'I design apps and teach Figma to beginners in Bangla, step by step.', skills: ['Figma'], experience: '3 years at an agency', portfolio: [{ type: 'LINK', title: 'Site', url: 'https://example.com' }] };
    await http.post(`${api}/teacher-applications`).set(auth('stud')).send(app).expect(400);
    const ok = await http.post(`${api}/teacher-applications`).set(auth('stud')).send({ ...app, acceptRules: true }).expect(201);
    expect(ok.body.rulesAcceptedAt).toBeTruthy();
  });

  it('a new instructor gets the blue tick (and paid courses) after the free-course, views and watch-time targets', async () => {
    await http.post(`${api}/teacher/courses`).set(auth('newbie')).send({ title: 'Paid one', description: 'Not allowed yet for a new instructor.', priceBdt: 999 }).expect(400);
    let st = (await http.get(`${api}/teacher/status`).set(auth('newbie')).expect(200)).body;
    expect(st.verification).toMatchObject({ verified: false, canSellPaid: false, freeCourses: 0, targets: { freeCourses: 10, views: 4000, watchMinutes: 10000 } });

    // ten free published courses with enough views and watch time
    const stud = await prisma.user.findUniqueOrThrow({ where: { id: id.stud } });
    for (let i = 0; i < 10; i++) {
      const c = await prisma.course.create({ data: { teacherId: id.newbie, title: `Free ${i}`, description: 'Free course', isFree: true, status: 'PUBLISHED', views: 400 } });
      const lesson = await prisma.lesson.create({ data: { section: { create: { courseId: c.id, title: 'S', position: 0 } }, title: 'L', durationSec: 60, position: 0 } });
      const e = await prisma.enrollment.create({ data: { userId: stud.id, courseId: c.id } });
      await prisma.lessonProgress.create({ data: { enrollmentId: e.id, lessonId: lesson.id, watchedSec: 60_000 } }); // 1,000 minutes each
    }
    st = (await http.get(`${api}/teacher/status`).set(auth('newbie')).expect(200)).body;
    expect(st.verification).toMatchObject({ verified: true, canSellPaid: true, freeCourses: 10, views: 4000, watchMinutes: 10000 });
    await http.post(`${api}/teacher/courses`).set(auth('newbie')).send({ title: 'Paid one', description: 'Allowed now with the blue tick.', priceBdt: 999 }).expect(201);
    const pub = (await http.get(`${api}/teachers/${id.newbie}`).expect(200)).body;
    expect(pub.verified).toBe(true);
  });

  it('opening a lesson counts a view, but not for the instructor', async () => {
    const c = await prisma.course.findFirstOrThrow({ where: { teacherId: id.newbie, title: 'Free 0' }, include: { sections: { include: { lessons: true } } } });
    const lessonId = c.sections[0].lessons[0].id;
    await http.get(`${api}/lessons/${lessonId}`).set(auth('stud')).expect(200);
    await http.get(`${api}/lessons/${lessonId}`).set(auth('newbie')).expect(200);
    expect((await prisma.course.findUniqueOrThrow({ where: { id: c.id } })).views).toBe(401);
  });

  it('more than 10 uploaded videos needs a storage plan; buying one lifts the limit', async () => {
    const course = await prisma.course.create({ data: { teacherId: id.pro, title: 'Many videos', description: 'Video course', isFree: true } });
    const section = await prisma.section.create({ data: { courseId: course.id, title: 'S', position: 0 } });
    const lessons = [];
    for (let i = 0; i < 11; i++) lessons.push(await prisma.lesson.create({ data: { sectionId: section.id, title: `L${i}`, position: i } }));
    for (let i = 0; i < 10; i++) await http.post(`${api}/teacher/lessons/${lessons[i].id}/video`).set(auth('pro')).attach('file', mp4, 'v.mp4').expect(201);
    const blocked = await http.post(`${api}/teacher/lessons/${lessons[10].id}/video`).set(auth('pro')).attach('file', mp4, 'v.mp4').expect(403);
    expect(blocked.body.code).toBe('STORAGE_LIMIT');
    // replacing an existing video is always fine
    await http.post(`${api}/teacher/lessons/${lessons[0].id}/video`).set(auth('pro')).attach('file', mp4, 'v.mp4').expect(201);

    const st = (await http.get(`${api}/teacher/status`).set(auth('pro')).expect(200)).body;
    expect(st.storage).toMatchObject({ plan: 'FREE', videos: 10, limit: 10 });
    expect(st.storage.plans.find((p: { plan: string }) => p.plan === 'STARTER')).toMatchObject({ videos: 50, monthlyPaisa: 19900, yearlyPaisa: 199000 });
    const buy = await http.post(`${api}/teacher/storage-plan`).set(auth('pro')).send({ plan: 'STARTER', months: 12 }).expect(201);
    expect(buy.body.amountPaisa).toBe(199000); // 12 months for the price of 10
    await pay(buy.body.tranId, 199000);
    const after = (await http.get(`${api}/teacher/status`).set(auth('pro')).expect(200)).body;
    expect(after.storage).toMatchObject({ plan: 'STARTER', limit: 50 });
    await http.post(`${api}/teacher/lessons/${lessons[10].id}/video`).set(auth('pro')).attach('file', mp4, 'v.mp4').expect(201);
  });

  let slotStart: string;
  it('1:1 price follows the session length; the instructor declines and the student is refunded', async () => {
    await http.patch(`${api}/teacher/profile`).set(auth('pro')).send({ experience: '8 years', expertise: ['Flutter', 'Firebase'], hourlyRateBdt: 600 }).expect(200);
    await http.put(`${api}/teacher/availability`).set(auth('pro')).send({
      rules: [0, 1, 2, 3, 4, 5, 6].map((weekday) => ({ weekday, startMinute: 0, endMinute: 1440, slotMinutes: 30, priceBdt: 1 })),
    }).expect(200);
    const slots = (await http.get(`${api}/teachers/${id.pro}/slots?days=3`).expect(200)).body;
    expect(slots[0].pricePaisa).toBe(30000); // 600 BDT/hour x 30 minutes
    slotStart = slots.find((s: { startAt: string }) => new Date(s.startAt).getTime() > Date.now() + 30 * 3600_000).startAt;
    const b = await http.post(`${api}/bookings`).set(auth('stud')).send({ teacherId: id.pro, startAt: slotStart }).expect(201);
    await pay(b.body.tranId, 30000);
    const list = (await http.get(`${api}/teacher/bookings`).set(auth('pro')).expect(200)).body;
    expect(list[0]).toMatchObject({ status: 'REQUESTED' });
    const declined = await http.post(`${api}/teacher/bookings/${b.body.booking.id}/decline`).set(auth('pro')).send({ note: 'I am travelling that day' }).expect(201);
    expect(declined.body).toMatchObject({ status: 'CANCELLED', cancelledBy: 'teacher', declineNote: 'I am travelling that day' });
    expect((await prisma.order.findUniqueOrThrow({ where: { id: b.body.orderId } })).status).toBe('REFUNDED');
    expect(await prisma.ledgerEntry.count({ where: { teacherId: id.pro } })).toBe(0);
    // the slot is free again
    const again = (await http.get(`${api}/teachers/${id.pro}/slots?days=3`)).body.map((s: { startAt: string }) => s.startAt);
    expect(again).toContain(slotStart);
  });

  it('a request nobody answers in time is declined automatically', async () => {
    await http.put(`${api}/teacher/availability`).set(auth('pro')).send({ rules: [{ weekday: new Date(slotStart).getUTCDay(), startMinute: 0, endMinute: 1440, slotMinutes: 30, priceBdt: 0 }] }).expect(200);
    const free = (await http.get(`${api}/teachers/${id.pro}/slots?days=7`)).body[0];
    const b = await http.post(`${api}/bookings`).set(auth('stud')).send({ teacherId: id.pro, startAt: free.startAt }).expect(201);
    expect(b.body.booking.status).toBe('REQUESTED'); // free sessions are requests too
    await prisma.booking.update({ where: { id: b.body.booking.id }, data: { respondBy: new Date(Date.now() - 1000) } });
    await app.get(require('../src/bookings/bookings.service').BookingsService).expireRequests();
    const after = await prisma.booking.findUniqueOrThrow({ where: { id: b.body.booking.id } });
    expect(after).toMatchObject({ status: 'CANCELLED', cancelledBy: 'system' });
  });

  it('course fee drops with the tier: 7% regular, 6% Silver, 5% Gold (+5% VAT)', async () => {
    const course = await prisma.course.create({ data: { teacherId: id.pro, title: 'Paid course', description: 'Paid', pricePaisa: 100000, isFree: false, status: 'PUBLISHED' } });
    // 25 earlier sales make the instructor Silver
    for (let i = 0; i < 25; i++) {
      const buyer = await prisma.user.create({ data: { name: `b${i}`, email: `b${i}@r.bd`, passwordHash: 'x' } });
      await prisma.order.create({ data: { userId: buyer.id, itemType: 'COURSE', itemId: course.id, amountPaisa: 100000, status: 'PAID', tranId: `T${i}` } });
    }
    expect((await http.get(`${api}/teacher/status`).set(auth('pro')).expect(200)).body).toMatchObject({ tier: 'SILVER', sales: 25, fees: { courseCommissionBps: 600 } });
    const c = await http.post(`${api}/checkout/course/${course.id}`).set(auth('stud')).expect(201);
    await pay(c.body.tranId, 100000);
    const entry = await prisma.ledgerEntry.findFirstOrThrow({ where: { orderId: c.body.orderId } });
    expect(entry).toMatchObject({ commissionBps: 600, commissionPaisa: 6000, vatPaisa: 5000, amountPaisa: 89000 });
    const breakdown = (await http.get(`${api}/teacher/earnings/breakdown`).set(auth('pro')).expect(200)).body;
    expect(breakdown[0]).toMatchObject({ grossPaisa: 100000, commissionPaisa: 6000, vatPaisa: 5000, amountPaisa: 89000 });
  });

  it('15 friends who buy a paid course give the referrer 15 days of free paid courses', async () => {
    const ref = (await http.get(`${api}/me/referral`).set(auth('stud')).expect(200)).body;
    expect(ref).toMatchObject({ joined: 0, qualified: 0, target: 15, passDays: 15, freePassUntil: null });
    const course = await prisma.course.findFirstOrThrow({ where: { title: 'Paid course' } });
    for (let i = 0; i < 15; i++) {
      const r = await http.post(`${api}/auth/register`).send({ name: `Friend ${i}`, email: `f${i}@r.bd`, password: 'password123', ref: ref.code.toLowerCase() }).expect(201);
      const c = await http.post(`${api}/checkout/course/${course.id}`).set({ Authorization: `Bearer ${r.body.accessToken}` }).expect(201);
      await pay(c.body.tranId, 100000);
    }
    const after = (await http.get(`${api}/me/referral`).set(auth('stud')).expect(200)).body;
    expect(after).toMatchObject({ joined: 15, qualified: 15, towardNext: 0 });
    expect(new Date(after.freePassUntil).getTime()).toBeGreaterThan(Date.now() + 14 * 864e5);
    // any paid course can now be started without paying, until the pass ends
    const other = await prisma.course.create({ data: { teacherId: id.pro, title: 'Another paid', description: 'Paid', pricePaisa: 50000, isFree: false, status: 'PUBLISHED' } });
    const e = await http.post(`${api}/courses/${other.id}/enroll`).set(auth('stud')).expect(201);
    expect(e.body.expiresAt).toBeTruthy();
    await prisma.enrollment.update({ where: { id: e.body.id }, data: { expiresAt: new Date(Date.now() - 1000) } });
    expect((await http.get(`${api}/courses/${other.id}`).set(auth('stud'))).body.enrolled).toBe(false);
  });

  it('affiliate: sign up, verify with NID + selfie, pay $5, get approved, earn 2% per sale; idle accounts close', async () => {
    const joined = (await http.post(`${api}/affiliates/join`).set(auth('aff')).expect(201)).body;
    expect(joined.status).toBe('UNPAID');
    const ups: string[] = [];
    for (let i = 0; i < 4; i++) ups.push((await http.post(`${api}/uploads?kind=KYC`).set(auth('aff')).attach('file', png, 'p.png').expect(201)).body.id);
    const [nidFrontId, nidBackId, photoId, selfieId] = ups;
    await http.put(`${api}/affiliates/me/verification`).set(auth('aff')).send({ nidNumber: '1234567890', nidFrontId, nidBackId, photoId, selfieId: id.stud }).expect(400);
    await http.put(`${api}/affiliates/me/verification`).set(auth('aff')).send({ nidNumber: '1234567890', nidFrontId, nidBackId, photoId, selfieId }).expect(200);
    await http.post(`${api}/admin/affiliates/${id.aff}/review`).set(auth('admin')).send({ decision: 'APPROVED' }).expect(400); // not paid yet
    const m = await http.post(`${api}/affiliates/me/membership`).set(auth('aff')).expect(201);
    expect(m.body.amountPaisa).toBe(60000);
    await pay(m.body.tranId, 60000);
    const queue = (await http.get(`${api}/admin/affiliates?status=IN_REVIEW`).set(auth('admin')).expect(200)).body;
    expect(queue).toHaveLength(1);
    const detail = (await http.get(`${api}/admin/affiliates/${id.aff}`).set(auth('admin')).expect(200)).body;
    expect(detail.documents.selfie).toContain('/files/');
    await http.post(`${api}/admin/affiliates/${id.aff}/review`).set(auth('admin')).send({ decision: 'APPROVED' }).expect(201);

    const course = await prisma.course.findFirstOrThrow({ where: { title: 'Paid course' } });
    await http.post(`${api}/affiliates/click`).send({ code: joined.code, courseId: course.id }).expect(201);
    const buyer = await http.post(`${api}/auth/register`).send({ name: 'Buyer', email: 'buyer@r.bd', password: 'password123' }).expect(201);
    const c = await http.post(`${api}/checkout/course/${course.id}?ref=${joined.code}`).set({ Authorization: `Bearer ${buyer.body.accessToken}` }).expect(201);
    await pay(c.body.tranId, 100000);
    const dash = (await http.get(`${api}/affiliates/me`).set(auth('aff')).expect(200)).body;
    expect(dash.profile.status).toBe('ACTIVE');
    expect(dash.totals).toMatchObject({ clicks: 1, sales: 1 });
    expect(dash.money.pendingPaisa).toBe(2000); // 2% of 1,000 BDT
    expect(dash.recent[0].courseTitle).toBe('Paid course');

    await prisma.affiliateEarning.updateMany({ data: { availableAt: new Date(Date.now() - 1000) } });
    await prisma.affiliateProfile.update({ where: { userId: id.aff }, data: { lastActiveAt: new Date(Date.now() - 181 * 864e5) } });
    expect(await app.get(GrowthService).daily()).toEqual({ matured: 1, deactivated: 1 });
    expect((await prisma.affiliateProfile.findUniqueOrThrow({ where: { userId: id.aff } })).status).toBe('DEACTIVATED');
  });
});
