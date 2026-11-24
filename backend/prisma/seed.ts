import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main() {
  const email = process.env.ADMIN_EMAIL;
  const password = process.env.ADMIN_PASSWORD;
  if (!email || !password) throw new Error('Set ADMIN_EMAIL and ADMIN_PASSWORD');

  const admin = await prisma.user.upsert({
    where: { email },
    create: { name: 'Tech.Dropout', email, passwordHash: await bcrypt.hash(password, 10) },
    update: {},
  });
  for (const role of ['ADMIN', 'STUDENT'] as const) {
    await prisma.userRole.upsert({ where: { userId_role: { userId: admin.id, role } }, create: { userId: admin.id, role }, update: {} });
  }
  // The admin also publishes official recorded courses, shown under this profile.
  await prisma.teacherProfile.upsert({
    where: { userId: admin.id },
    create: { userId: admin.id, headline: 'Official Tech.Dropout courses', bio: 'Courses made by the Tech.Dropout team.', skills: [] },
    update: {},
  });
  await prisma.platformSettings.upsert({ where: { id: 1 }, create: { id: 1 }, update: {} });

  // name, slug, app icon, chip colour (from the logo palette and friends)
  const categories = [
    ['Web Development', 'web-development', 'code', '#355457'],
    ['App Development', 'app-development', 'phone', '#2F6F8F'],
    ['Graphics Design', 'graphics-design', 'brush', '#E07A45'],
    ['Digital Marketing', 'digital-marketing', 'campaign', '#B5508A'],
    ['Freelancing', 'freelancing', 'work', '#3E8E6A'],
    ['Spoken English', 'spoken-english', 'translate', '#6B5BD2'],
    ['Data & AI', 'data-ai', 'analytics', '#1F7A8C'],
    ['Office & Productivity', 'office-productivity', 'table', '#8C6D1F'],
  ];
  for (const [i, [name, slug, icon, color]] of categories.entries()) {
    const existing = await prisma.category.findUnique({ where: { slug } });
    if (!existing) await prisma.category.create({ data: { name, slug, icon, color, position: i } });
    else if (!existing.icon) await prisma.category.update({ where: { slug }, data: { icon, color, position: i } });
  }
  console.log(`Admin ready: ${email}`);
}

main().finally(() => prisma.$disconnect());
