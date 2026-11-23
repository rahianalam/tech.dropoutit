import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as bcrypt from 'bcryptjs';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/prisma/prisma.service';
import { FcmClient } from '../src/push/fcm';
import { PushService } from '../src/push/push.module';
import { configureApp } from '../src/setup';

describe('push + account deletion (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let http: ReturnType<typeof request>;
  const api = '/api/v1';
  const t: Record<string, string> = {};
  const auth = (who: string) => ({ Authorization: `Bearer ${t[who]}` });
  const sent: { token: string; title: string }[] = [];
  const fakeFcm = {
    enabled: true,
    send: async (token: string, title: string) => {
      sent.push({ token, title });
      return token.startsWith('dead') ? 'invalid-token' : 'ok';
    },
  };
  const tokenA = 'phone-a-' + 'x'.repeat(30);
  const dead = 'dead-' + 'y'.repeat(30);

  beforeAll(async () => {
    const mod = await Test.createTestingModule({ imports: [AppModule] }).overrideProvider(FcmClient).useValue(fakeFcm).compile();
    app = mod.createNestApplication();
    configureApp(app);
    await app.init();
    prisma = app.get(PrismaService);
    http = request(app.getHttpServer());
    const tables = await prisma.$queryRaw<{ tablename: string }[]>`SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename <> '_prisma_migrations'`;
    await prisma.$executeRawUnsafe(`TRUNCATE ${tables.map((x) => `"${x.tablename}"`).join(',')} CASCADE`);
    const hash = await bcrypt.hash('password123', 10);
    await prisma.user.create({ data: { name: 'Admin', email: 'admin@r.bd', passwordHash: hash, roles: { create: [{ role: 'ADMIN' }] } } });
    for (const n of ['u1', 'u2']) await prisma.user.create({ data: { name: n, email: `${n}@r.bd`, passwordHash: hash, roles: { create: [{ role: 'STUDENT' }] } } });
    for (const who of ['admin', 'u1', 'u2']) {
      t[who] = (await http.post(`${api}/auth/login`).send({ identifier: `${who}@r.bd`, password: 'password123' })).body.accessToken;
    }
  });
  afterAll(async () => app.close());

  it('a phone token moves to whoever signed in last, and logout removes it', async () => {
    await http.post(`${api}/me/devices`).set(auth('u1')).send({ token: tokenA, platform: 'ANDROID' }).expect(204);
    await http.post(`${api}/me/devices`).set(auth('u2')).send({ token: tokenA, platform: 'ANDROID' }).expect(204);
    expect((await prisma.deviceToken.findUniqueOrThrow({ where: { token: tokenA } })).userId).toBe((await prisma.user.findFirstOrThrow({ where: { email: 'u2@r.bd' } })).id);
    await http.delete(`${api}/me/devices/${tokenA}`).set(auth('u1')).expect(204); // not theirs: no effect
    expect(await prisma.deviceToken.count()).toBe(1);
    await http.post(`${api}/me/devices`).set(auth('u1')).send({ token: tokenA, platform: 'ANDROID' }).expect(204);
  });

  it('new notifications are pushed once; old ones and dead tokens are skipped', async () => {
    const u1 = await prisma.user.findFirstOrThrow({ where: { email: 'u1@r.bd' } });
    await prisma.deviceToken.create({ data: { token: dead, userId: u1.id, platform: 'ANDROID' } });
    await prisma.notification.create({ data: { userId: u1.id, title: 'old', body: '', createdAt: new Date(Date.now() - 3600_000) } });
    await prisma.notification.create({ data: { userId: u1.id, title: 'নতুন বুকিং', body: 'Karim' } });
    const push = app.get(PushService);
    expect(await push.sendPending()).toBe(1);
    expect(sent.map((s) => s.title)).toEqual(['নতুন বুকিং', 'নতুন বুকিং']);
    expect(await prisma.deviceToken.findUnique({ where: { token: dead } })).toBeNull();
    expect(await push.sendPending()).toBe(0); // not sent twice
  });

  it('deleting an account needs the password and wipes personal data', async () => {
    await http.post(`${api}/auth/delete-account`).set(auth('u1')).send({ password: 'wrong' }).expect(401);
    await http.post(`${api}/auth/delete-account`).set(auth('admin')).send({ password: 'password123' }).expect(403);
    await http.post(`${api}/auth/delete-account`).set(auth('u1')).send({ password: 'password123' }).expect(204);
    const u = await prisma.user.findFirstOrThrow({ where: { name: 'মুছে ফেলা অ্যাকাউন্ট' } });
    expect(u).toMatchObject({ email: null, phone: null, status: 'DELETED' });
    expect(await prisma.deviceToken.count({ where: { userId: u.id } })).toBe(0);
    await http.get(`${api}/auth/me`).set(auth('u1')).expect(401);
    await http.post(`${api}/auth/login`).send({ identifier: 'u1@r.bd', password: 'password123' }).expect(401);
    // the email can be used again for a new account
    await http.post(`${api}/auth/register`).send({ name: 'New u1', email: 'u1@r.bd', password: 'password123' }).expect(201);
  });
});

describe('store pages', () => {
  let app: INestApplication;
  beforeAll(async () => {
    const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = mod.createNestApplication();
    configureApp(app);
    await app.init();
  });
  afterAll(async () => app.close());

  it('serves the privacy policy and deletion instructions without login', async () => {
    const p = await request(app.getHttpServer()).get('/privacy').expect(200);
    expect(p.headers['content-type']).toContain('text/html');
    expect(p.text).toContain('প্রাইভেসি পলিসি');
    await request(app.getHttpServer()).get('/delete-account').expect(200);
  });
});
