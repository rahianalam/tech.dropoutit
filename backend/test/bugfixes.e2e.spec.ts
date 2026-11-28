import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as bcrypt from 'bcryptjs';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { generateSlots } from '../src/bookings/slots';
import { PrismaService } from '../src/prisma/prisma.service';
import { configureApp } from '../src/setup';

describe('slot generation with bookings of another length', () => {
  const now = new Date('2026-11-28T12:00:00Z');
  const rule = { weekday: 0, startMinute: 19 * 60, endMinute: 21 * 60, slotMinutes: 30, pricePaisa: 50000, timezone: 'Asia/Dhaka' };

  it('a 60-minute booking blocks both 30-minute slots it covers', () => {
    // 7–8 PM Dhaka booked when the teacher still used 60-minute slots
    const booked = [{ startAt: new Date('2026-11-29T13:00:00Z'), endAt: new Date('2026-11-29T14:00:00Z') }];
    const free = generateSlots([rule], booked, now, 7, now).map((s) => s.startAt.toISOString());
    expect(free).toEqual(['2026-11-29T14:00:00.000Z', '2026-11-29T14:30:00.000Z']);
  });
});

/** Regression tests for the bugs fixed in the bug-hunt PR. */
describe('bug fixes (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let http: ReturnType<typeof request>;
  const api = '/api/v1';
  const t: Record<string, string> = {};
  const id: Record<string, string> = {};
  const refresh: Record<string, string> = {};
  const auth = (who: string) => ({ Authorization: `Bearer ${t[who]}` });
  const pay = (tranId: string, amount: number) =>
    http.post(`${api}/payments/sslcommerz/ipn`).type('form').send({ val_id: `ok:${tranId}:${amount}` }).expect(200, { received: true, ok: true });
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
    await prisma.platformSettings.create({ data: { id: 1, minPayoutPaisa: 0 } });
    const hash = await bcrypt.hash('password123', 10);
    const make = async (who: string, roles: string[], profile?: object) => {
      const u = await prisma.user.create({
        data: {
          name: who, email: `${who}@x.bd`, passwordHash: hash, roles: { create: roles.map((role) => ({ role: role as 'STUDENT' })) },
          ...(profile ? { teacherProfile: { create: { headline: 'H', bio: 'B', skills: [], ...profile } } } : {}),
        },
      });
      id[who] = u.id;
      const r = (await http.post(`${api}/auth/login`).send({ identifier: `${who}@x.bd`, password: 'password123' }).expect(200)).body;
      t[who] = r.accessToken;
      refresh[who] = r.refreshToken;
    };
    await make('admin', ['ADMIN']);
    await make('teach', ['TEACHER'], { canSellPaid: true });
    await make('s1', ['STUDENT']);
    await make('s2', ['STUDENT']);
    await make('s3', ['STUDENT']);
    await make('aff', ['STUDENT', 'AFFILIATE']);
    await prisma.affiliateProfile.create({ data: { userId: id.aff, code: 'AFFCODE', status: 'ACTIVE', membershipPaidAt: new Date(), lastActiveAt: new Date() } });

    const c = await prisma.course.create({
      data: {
        teacherId: id.teach, title: 'Paid course', description: 'A paid course used by the regression tests.', pricePaisa: 100000, isFree: false, status: 'PUBLISHED',
        sections: { create: { title: 'One', position: 0, lessons: { create: { title: 'L1', position: 0, durationSec: 60 } } } },
      },
      include: { sections: { include: { lessons: true } } },
    });
    courseId = c.id;
    lessonId = c.sections[0].lessons[0].id;
  });

  afterAll(async () => app.close());

  it('refunding a sale voids the affiliate cut and lowers the unsent payout', async () => {
    const buy = async (who: string) => {
      const r = (await http.post(`${api}/checkout/course/${courseId}?ref=AFFCODE`).set(auth(who)).expect(201)).body;
      await pay(r.tranId, r.amountPaisa);
      return r.orderId as string;
    };
    const o1 = await buy('s1');
    await buy('s2');
    expect(await prisma.affiliateEarning.count({ where: { affiliateId: id.aff, status: 'PENDING' } })).toBe(2);

    await prisma.ledgerEntry.updateMany({ where: { teacherId: id.teach }, data: { availableAt: new Date(Date.now() - 1000) } });
    const drafts = (await http.post(`${api}/admin/payouts/generate`).set(auth('admin')).expect(201)).body;
    expect(drafts).toHaveLength(1);
    const each = (await prisma.ledgerEntry.findFirstOrThrow({ where: { orderId: o1 } })).amountPaisa;
    expect(drafts[0].amountPaisa).toBe(2 * each);

    await http.post(`${api}/admin/orders/${o1}/refund`).set(auth('admin')).expect(201);
    expect((await prisma.payout.findUniqueOrThrow({ where: { id: drafts[0].id } })).amountPaisa).toBe(each);
    expect((await prisma.affiliateEarning.findUniqueOrThrow({ where: { orderId: o1 } })).status).toBe('VOID');
  });

  it('a student whose free pass ran out can buy the course and keeps it for good', async () => {
    await prisma.enrollment.create({ data: { userId: id.s3, courseId, expiresAt: new Date(Date.now() - 864e5) } });
    // the expired pass course is gone from My Learning and its lessons are locked
    expect((await http.get(`${api}/me/enrollments`).set(auth('s3')).expect(200)).body).toHaveLength(0);
    await http.post(`${api}/lessons/${lessonId}/progress`).set(auth('s3')).send({ watchedSec: 10 }).expect(403);

    const r = (await http.post(`${api}/checkout/course/${courseId}`).set(auth('s3')).expect(201)).body;
    await pay(r.tranId, r.amountPaisa);
    const e = await prisma.enrollment.findUniqueOrThrow({ where: { userId_courseId: { userId: id.s3, courseId } } });
    expect(e).toMatchObject({ status: 'ACTIVE', expiresAt: null });
    await http.get(`${api}/lessons/${lessonId}`).set(auth('s3')).expect(200);
  });

  it('an admin refund of a booking opens the slot again', async () => {
    const everyDay = [0, 1, 2, 3, 4, 5, 6].map((weekday) => ({ weekday, startMinute: 0, endMinute: 1440, slotMinutes: 60, priceBdt: 500 }));
    await http.put(`${api}/teacher/availability`).set(auth('teach')).send({ rules: everyDay }).expect(200);
    const slot = (await http.get(`${api}/teachers/${id.teach}/slots?days=3`).expect(200)).body.at(-1).startAt as string;
    const b = (await http.post(`${api}/bookings`).set(auth('s1')).send({ teacherId: id.teach, startAt: slot }).expect(201)).body;
    await pay(b.tranId, b.amountPaisa);
    await http.post(`${api}/teacher/bookings/${b.booking.id}/accept`).set(auth('teach')).expect(201);
    const open = async () => (await http.get(`${api}/teachers/${id.teach}/slots?days=3`)).body.some((s: { startAt: string }) => s.startAt === slot);
    expect(await open()).toBe(false);

    await http.post(`${api}/admin/orders/${b.orderId}/refund`).set(auth('admin')).expect(201);
    expect(await open()).toBe(true);
    await http.post(`${api}/bookings`).set(auth('s2')).send({ teacherId: id.teach, startAt: slot }).expect(201);
  });

  it('a deactivated affiliate who pays again is active again', async () => {
    await prisma.affiliateProfile.update({ where: { userId: id.aff }, data: { status: 'DEACTIVATED' } });
    const r = (await http.post(`${api}/affiliates/me/membership`).set(auth('aff')).expect(201)).body;
    await pay(r.tranId, r.amountPaisa);
    expect((await prisma.affiliateProfile.findUniqueOrThrow({ where: { userId: id.aff } })).status).toBe('ACTIVE');
  });

  it('a refresh token works once, and a blocked account gets no new tokens', async () => {
    const first = await http.post(`${api}/auth/refresh`).send({ refreshToken: refresh.s2 }).expect(200);
    await http.post(`${api}/auth/refresh`).send({ refreshToken: refresh.s2 }).expect(401);
    await prisma.user.update({ where: { id: id.s2 }, data: { status: 'BLOCKED' } });
    await http.post(`${api}/auth/refresh`).send({ refreshToken: first.body.refreshToken }).expect(401);
  });

  it('the referral target cannot be set to 0', async () => {
    await http.patch(`${api}/admin/settings`).set(auth('admin')).send({ referralTarget: 0 }).expect(400);
  });
});
