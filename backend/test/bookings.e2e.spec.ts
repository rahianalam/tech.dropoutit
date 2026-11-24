import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as bcrypt from 'bcryptjs';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { BookingsService } from '../src/bookings/bookings.service';
import { generateSlots } from '../src/bookings/slots';
import { PrismaService } from '../src/prisma/prisma.service';
import { configureApp } from '../src/setup';

describe('slot generation', () => {
  // Sunday 2026-11-29 00:00 Dhaka = 2026-11-28T18:00Z
  const now = new Date('2026-11-28T12:00:00Z');
  const rule = { weekday: 0, startMinute: 19 * 60, endMinute: 21 * 60, slotMinutes: 60, pricePaisa: 50000, timezone: 'Asia/Dhaka' };

  it('turns a weekly window into slots in Dhaka time', () => {
    const slots = generateSlots([rule], [], now, 7, now);
    expect(slots.map((s) => s.startAt.toISOString())).toEqual(['2026-11-29T13:00:00.000Z', '2026-11-29T14:00:00.000Z']); // 7 PM and 8 PM Dhaka
  });

  it('skips taken slots and slots inside the 2-hour lead time', () => {
    const taken = [new Date('2026-11-29T13:00:00Z')];
    expect(generateSlots([rule], taken, now, 7, now)).toHaveLength(1);
    const late = new Date('2026-11-29T12:30:00Z'); // 6:30 PM Dhaka on that Sunday
    expect(generateSlots([rule], [], late, 1, late)).toHaveLength(0);
  });
});

describe('bookings (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let http: ReturnType<typeof request>;
  const api = '/api/v1';
  const t: Record<string, string> = {};
  const auth = (who: string) => ({ Authorization: `Bearer ${t[who]}` });
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
    await prisma.user.create({ data: { name: 'Admin', email: 'admin@b.bd', passwordHash: hash, roles: { create: [{ role: 'ADMIN' }] } } });
    const teacher = await prisma.user.create({
      data: { name: 'Teacher', email: 'teacher@b.bd', passwordHash: hash, roles: { create: [{ role: 'TEACHER' }] }, teacherProfile: { create: { headline: 'T', bio: 'B', skills: [], canSellPaid: true } } },
    });
    teacherId = teacher.id;
    for (const n of ['s1', 's2']) await prisma.user.create({ data: { name: n, email: `${n}@b.bd`, passwordHash: hash, roles: { create: [{ role: 'STUDENT' }] } } });
    for (const who of ['admin', 'teacher', 's1', 's2']) {
      t[who] = (await http.post(`${api}/auth/login`).send({ identifier: `${who}@b.bd`, password: 'password123' })).body.accessToken;
    }
  });
  afterAll(async () => app.close());

  it('teacher sets a weekly schedule; overlaps are rejected', async () => {
    const everyDay = [0, 1, 2, 3, 4, 5, 6].map((weekday) => ({ weekday, startMinute: 0, endMinute: 1440, slotMinutes: 60, priceBdt: 500 }));
    await http.put(`${api}/teacher/availability`).set(auth('teacher'))
      .send({ rules: [{ weekday: 1, startMinute: 600, endMinute: 720, slotMinutes: 60, priceBdt: 500 }, { weekday: 1, startMinute: 660, endMinute: 780, slotMinutes: 60, priceBdt: 500 }] }).expect(400);
    const r = await http.put(`${api}/teacher/availability`).set(auth('teacher')).send({ rules: everyDay }).expect(200);
    expect(r.body).toHaveLength(7);
  });

  let slot: string;
  let bookingId: string;

  it('lists free slots and holds one while the student pays; a second student is blocked', async () => {
    const slots = await http.get(`${api}/teachers/${teacherId}/slots?days=3`).expect(200);
    expect(slots.body.length).toBeGreaterThan(20);
    // pick a slot 3 days out so the 24-hour cancel window is open
    slot = slots.body.find((s: { startAt: string }) => new Date(s.startAt).getTime() > Date.now() + 50 * 3600_000)?.startAt ?? slots.body.at(-1).startAt;
    const b = await http.post(`${api}/bookings`).set(auth('s1')).send({ teacherId, startAt: slot }).expect(201);
    expect(b.body.booking.status).toBe('HELD');
    expect(b.body.gatewayUrl).toContain('/payments/fake/checkout');
    bookingId = b.body.booking.id;

    await http.post(`${api}/bookings`).set(auth('s2')).send({ teacherId, startAt: slot }).expect(409);
    const after = await http.get(`${api}/teachers/${teacherId}/slots?days=3`).expect(200);
    expect(after.body.map((s: { startAt: string }) => s.startAt)).not.toContain(slot);

    // paying turns it into a request; the money waits with the platform until the instructor accepts
    await http.post(`${api}/payments/sslcommerz/ipn`).type('form').send({ val_id: `ok:${b.body.tranId}:50000` }).expect(200, { received: true, ok: true });
    let mine = await http.get(`${api}/me/bookings`).set(auth('s1')).expect(200);
    expect(mine.body[0]).toMatchObject({ status: 'REQUESTED' });
    expect(mine.body[0].respondBy).toBeTruthy();
    expect(await prisma.ledgerEntry.count({ where: { teacherId } })).toBe(0);
    await http.post(`${api}/teacher/bookings/${bookingId}/accept`).set(auth('s2')).expect(403);
    await http.post(`${api}/teacher/bookings/${bookingId}/accept`).set(auth('teacher')).expect(201);
    await http.post(`${api}/teacher/bookings/${bookingId}/accept`).set(auth('teacher')).expect(409);
    mine = await http.get(`${api}/me/bookings`).set(auth('s1')).expect(200);
    expect(mine.body[0]).toMatchObject({ status: 'CONFIRMED' });
    expect(mine.body[0].meetingUrl).toMatch(/^https:\/\/meet\.jit\.si\/techdropout-/);
    const entry = await prisma.ledgerEntry.findFirstOrThrow({ where: { teacherId } });
    // 500 BDT session: 10% platform fee + 5% VAT; held until after the session
    expect(entry).toMatchObject({ commissionBps: 1000, amountPaisa: 42500, commissionPaisa: 5000, vatPaisa: 2500 });
    const booking = await prisma.booking.findUniqueOrThrow({ where: { id: bookingId } });
    expect(entry.availableAt!.getTime()).toBeGreaterThan(booking.endAt.getTime());
    const teacherList = await http.get(`${api}/teacher/bookings`).set(auth('teacher')).expect(200);
    expect(teacherList.body).toHaveLength(1);
  });

  it('an expired hold frees the slot for someone else', async () => {
    const slots = (await http.get(`${api}/teachers/${teacherId}/slots?days=3`)).body;
    const other = slots.at(-1).startAt;
    const held = await http.post(`${api}/bookings`).set(auth('s1')).send({ teacherId, startAt: other }).expect(201);
    await prisma.booking.update({ where: { id: held.body.booking.id }, data: { heldUntil: new Date(Date.now() - 1000) } });
    await http.post(`${api}/bookings`).set(auth('s2')).send({ teacherId, startAt: other }).expect(201);
    // s1 pays late: the slot is gone, so no confirmation and no teacher earning
    await http.post(`${api}/payments/sslcommerz/ipn`).type('form').send({ val_id: `ok:${held.body.tranId}:50000` }).expect(200);
    const b = await prisma.booking.findUniqueOrThrow({ where: { id: held.body.booking.id } });
    expect(b.status).toBe('CANCELLED');
    expect(await prisma.ledgerEntry.count({ where: { teacherId } })).toBe(1);
  });

  it('student cancels more than 24 hours ahead and is refunded; the slot reopens', async () => {
    const r = await http.post(`${api}/bookings/${bookingId}/cancel`).set(auth('s1')).expect(201);
    expect(r.body).toMatchObject({ status: 'CANCELLED', cancelledBy: 'student' });
    const order = await prisma.order.findFirstOrThrow({ where: { itemId: bookingId } });
    expect(order.status).toBe('REFUNDED');
    expect((await prisma.ledgerEntry.findFirstOrThrow({ where: { orderId: order.id } })).status).toBe('VOID');
    const slots = (await http.get(`${api}/teachers/${teacherId}/slots?days=3`)).body.map((s: { startAt: string }) => s.startAt);
    expect(slots).toContain(slot);
  });

  it('a started session can be completed by the teacher and then reviewed', async () => {
    const past = await prisma.booking.create({
      data: { teacherId, studentId: (await prisma.user.findFirstOrThrow({ where: { email: 's2@b.bd' } })).id, startAt: new Date(Date.now() - 3600_000), endAt: new Date(), status: 'CONFIRMED', pricePaisa: 0 },
    });
    await http.post(`${api}/bookings/${past.id}/cancel`).set(auth('s2')).expect(400); // too late for the student
    await http.post(`${api}/bookings/${past.id}/review`).set(auth('s2')).send({ rating: 5 }).expect(400);
    await http.post(`${api}/bookings/${past.id}/complete`).set(auth('s2')).send({ outcome: 'COMPLETED' }).expect(403);
    await http.post(`${api}/bookings/${past.id}/complete`).set(auth('teacher')).send({ outcome: 'COMPLETED' }).expect(201);
    await http.post(`${api}/bookings/${past.id}/review`).set(auth('s2')).send({ rating: 5, comment: 'দারুণ' }).expect(201);
    await http.post(`${api}/bookings/${past.id}/report`).set(auth('s2')).send({ reason: 'Test report' }).expect(201);
    const adminNotes = await http.get(`${api}/me/notifications`).set(auth('admin')).expect(200);
    expect(adminNotes.body.some((n: { title: string }) => n.title === 'সেশন নিয়ে অভিযোগ')).toBe(true);
  });

  it('sends each reminder once', async () => {
    const s1 = await prisma.user.findFirstOrThrow({ where: { email: 's1@b.bd' } });
    await prisma.booking.create({
      data: { teacherId, studentId: s1.id, startAt: new Date(Date.now() + 10 * 60_000), endAt: new Date(Date.now() + 70 * 60_000), status: 'CONFIRMED' },
    });
    const svc = app.get(BookingsService);
    expect(await svc.sendReminders()).toEqual({ day: 1, soon: 1 });
    expect(await svc.sendReminders()).toEqual({ day: 0, soon: 0 });
  });
});
