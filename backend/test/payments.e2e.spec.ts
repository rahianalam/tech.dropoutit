import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as bcrypt from 'bcryptjs';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { teacherShare } from '../src/payments/payments.service';
import { isPayoutDay } from '../src/payouts/payouts.service';
import { PrismaService } from '../src/prisma/prisma.service';
import { configureApp } from '../src/setup';

describe('money rules', () => {
  it('teacher share = (paid - fee) x (1 - commission)', () => {
    expect(teacherShare(150000, 3000, 3000)).toBe(102900); // (1500 - 30) x 70% = 1029 BDT
    expect(teacherShare(100000, 0, 2000)).toBe(80000);
  });
  it('payout days follow the admin schedule in Dhaka time', () => {
    // 2026-12-31 20:00 UTC is 2027-01-01 02:00 in Dhaka
    expect(isPayoutDay('MONTHLY', 1, new Date('2026-12-31T20:00:00Z'))).toBe(true);
    expect(isPayoutDay('MONTHLY', 1, new Date('2026-12-31T10:00:00Z'))).toBe(false);
    expect(isPayoutDay('WEEKLY', 1, new Date('2026-11-29T06:00:00Z'))).toBe(true); // Sunday
    expect(isPayoutDay('MANUAL', 1, new Date())).toBe(false);
  });
});

/** Paid course → checkout → gateway callback → enrollment → teacher ledger → payout → refund. */
describe('payments and payouts (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let http: ReturnType<typeof request>;
  const api = '/api/v1';
  const t: Record<string, string> = {};
  const auth = (who: string) => ({ Authorization: `Bearer ${t[who]}` });
  let courseId: string;
  let teacherId: string;

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
    await prisma.user.create({ data: { name: 'Admin', email: 'admin@pay.bd', passwordHash: hash, roles: { create: [{ role: 'ADMIN' }] } } });
    const teacher = await prisma.user.create({
      data: { name: 'Teacher', email: 'teacher@pay.bd', passwordHash: hash, roles: { create: [{ role: 'TEACHER' }] }, teacherProfile: { create: { headline: 'T', bio: 'B', skills: [] } } },
    });
    teacherId = teacher.id;
    await prisma.user.create({ data: { name: 'Student', email: 'student@pay.bd', passwordHash: hash, roles: { create: [{ role: 'STUDENT' }] } } });
    for (const who of ['admin', 'teacher', 'student']) {
      t[who] = (await http.post(`${api}/auth/login`).send({ identifier: `${who}@pay.bd`, password: 'password123' })).body.accessToken;
    }
    const course = await prisma.course.create({
      data: { teacherId, title: 'Paid course', description: 'A paid course for testing.', pricePaisa: 150000, isFree: false, status: 'PUBLISHED', publishedAt: new Date() },
    });
    courseId = course.id;
  });

  afterAll(async () => app.close());

  let orderId: string;
  let tranId: string;

  it('checkout creates one pending order and returns the gateway URL', async () => {
    const r1 = await http.post(`${api}/checkout/course/${courseId}`).set(auth('student')).expect(201);
    expect(r1.body.gatewayUrl).toContain('/payments/fake/checkout');
    const r2 = await http.post(`${api}/checkout/course/${courseId}`).set(auth('student')).expect(201);
    expect(r2.body.orderId).toBe(r1.body.orderId); // double tap reuses the order
    orderId = r1.body.orderId;
    tranId = r1.body.tranId;
    await http.post(`${api}/checkout/course/${courseId}`).set(auth('teacher')).expect(403);
  });

  it('rejects a forged callback and an amount mismatch', async () => {
    await http.post(`${api}/payments/sslcommerz/ipn`).type('form').send({ val_id: `bad:${tranId}:150000`, tran_id: tranId }).expect(200, { received: true, ok: false });
    await http.post(`${api}/payments/sslcommerz/ipn`).type('form').send({ val_id: `ok:${tranId}:100`, tran_id: tranId }).expect(200, { received: true, ok: false });
    const o = await http.get(`${api}/orders/${orderId}`).set(auth('student')).expect(200);
    expect(o.body.status).toBe('PENDING');
  });

  it('a verified IPN enrolls the student and credits the teacher once', async () => {
    const valId = `ok:${tranId}:150000`;
    await http.post(`${api}/payments/sslcommerz/ipn`).type('form').send({ val_id: valId, tran_id: tranId }).expect(200, { received: true, ok: true });
    // The browser's success redirect arrives too; nothing is counted twice.
    const page = await http.post(`${api}/payments/sslcommerz/success`).type('form').send({ val_id: valId, tran_id: tranId }).expect(201);
    expect(page.text).toContain('পেমেন্ট সফল');

    const o = await http.get(`${api}/orders/${orderId}`).set(auth('student')).expect(200);
    expect(o.body.status).toBe('PAID');
    const detail = await http.get(`${api}/courses/${courseId}`).set(auth('student')).expect(200);
    expect(detail.body.enrolled).toBe(true);

    const entries = await prisma.ledgerEntry.findMany({ where: { teacherId } });
    expect(entries).toHaveLength(1);
    // fake gateway fee 2% = 3000 paisa; default commission 30%
    expect(entries[0]).toMatchObject({ amountPaisa: 102900, commissionBps: 3000, status: 'PENDING' });
    expect(await prisma.payment.count({ where: { orderId } })).toBe(1);
  });

  it('earnings stay pending during the hold, then become available and get paid out', async () => {
    let e = await http.get(`${api}/teacher/earnings`).set(auth('teacher')).expect(200);
    expect(e.body).toMatchObject({ pendingPaisa: 102900, availablePaisa: 0 });

    // nothing to pay yet
    expect((await http.post(`${api}/admin/payouts/generate`).set(auth('admin')).expect(201)).body).toHaveLength(0);

    await prisma.ledgerEntry.updateMany({ where: { teacherId }, data: { availableAt: new Date(Date.now() - 1000) } }); // hold passed
    await http.patch(`${api}/teacher/payout-account`).set(auth('teacher')).send({ method: 'bkash', account: '01711111111' }).expect(200);
    e = await http.get(`${api}/teacher/earnings`).set(auth('teacher')).expect(200);
    expect(e.body).toMatchObject({ pendingPaisa: 0, availablePaisa: 102900 });

    const drafts = (await http.post(`${api}/admin/payouts/generate`).set(auth('admin')).expect(201)).body;
    expect(drafts).toHaveLength(1);
    expect(drafts[0]).toMatchObject({ amountPaisa: 102900, method: 'bkash', account: '01711111111', status: 'DRAFT' });
    // generating again does not double-count
    expect((await http.post(`${api}/admin/payouts/generate`).set(auth('admin')).expect(201)).body).toHaveLength(0);

    await http.post(`${api}/admin/payouts/${drafts[0].id}/paid`).set(auth('admin')).send({ reference: 'BK123' }).expect(409);
    await http.post(`${api}/admin/payouts/${drafts[0].id}/approve`).set(auth('admin')).expect(201);
    const paid = await http.post(`${api}/admin/payouts/${drafts[0].id}/paid`).set(auth('admin')).send({ reference: 'BK123' }).expect(201);
    expect(paid.body.status).toBe('PAID');
    e = await http.get(`${api}/teacher/earnings`).set(auth('teacher')).expect(200);
    expect(e.body).toMatchObject({ availablePaisa: 0, paidPaisa: 102900 });
  });

  it('refund after payout removes access and claws back from the next payout', async () => {
    await http.post(`${api}/admin/orders/${orderId}/refund`).set(auth('admin')).expect(201);
    await http.post(`${api}/admin/orders/${orderId}/refund`).set(auth('admin')).expect(409);
    const detail = await http.get(`${api}/courses/${courseId}`).set(auth('student')).expect(200);
    expect(detail.body.enrolled).toBe(false);
    const e = await http.get(`${api}/teacher/earnings`).set(auth('teacher')).expect(200);
    expect(e.body.availablePaisa).toBe(-102900);
    const rev = await http.get(`${api}/admin/revenue`).set(auth('admin')).expect(200);
    expect(rev.body.paidOrders).toBe(0);
  });

  it("the admin's own course pays nothing out", async () => {
    const admin = await prisma.user.findFirstOrThrow({ where: { email: 'admin@pay.bd' } });
    const own = await prisma.course.create({
      data: { teacherId: admin.id, title: 'Official', description: 'Official course for testing.', pricePaisa: 50000, isFree: false, status: 'PUBLISHED' },
    });
    const c = await http.post(`${api}/checkout/course/${own.id}`).set(auth('student')).expect(201);
    await http.post(`${api}/payments/sslcommerz/ipn`).type('form').send({ val_id: `ok:${c.body.tranId}:50000` }).expect(200, { received: true, ok: true });
    expect(await prisma.ledgerEntry.count({ where: { teacherId: admin.id } })).toBe(0);
  });

  it('a cancelled checkout is marked failed', async () => {
    const other = await prisma.course.create({
      data: { teacherId, title: 'Another', description: 'Another paid course.', pricePaisa: 20000, isFree: false, status: 'PUBLISHED' },
    });
    const c = await http.post(`${api}/checkout/course/${other.id}`).set(auth('student')).expect(201);
    await http.post(`${api}/payments/sslcommerz/cancel`).type('form').send({ tran_id: c.body.tranId }).expect(201);
    expect((await prisma.order.findUniqueOrThrow({ where: { id: c.body.orderId } })).status).toBe('FAILED');
  });
});
