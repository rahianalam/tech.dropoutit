import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main() {
  const email = process.env.ADMIN_EMAIL;
  const password = process.env.ADMIN_PASSWORD;
  if (!email || !password) throw new Error('Set ADMIN_EMAIL and ADMIN_PASSWORD');

  const admin = await prisma.user.upsert({
    where: { email },
    create: { name: 'Admin', email, passwordHash: await bcrypt.hash(password, 10) },
    update: {},
  });
  for (const role of ['ADMIN', 'STUDENT'] as const) {
    await prisma.userRole.upsert({ where: { userId_role: { userId: admin.id, role } }, create: { userId: admin.id, role }, update: {} });
  }
  await prisma.platformSettings.upsert({ where: { id: 1 }, create: { id: 1 }, update: {} });

  const categories = [
    ['Web Development', 'web-development'],
    ['App Development', 'app-development'],
    ['Graphics Design', 'graphics-design'],
    ['Digital Marketing', 'digital-marketing'],
    ['Freelancing', 'freelancing'],
    ['Spoken English', 'spoken-english'],
  ];
  for (const [name, slug] of categories) {
    await prisma.category.upsert({ where: { slug }, create: { name, slug }, update: {} });
  }
  console.log(`Admin ready: ${email}`);
}

main().finally(() => prisma.$disconnect());
