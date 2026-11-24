/**
 * Emergency admin login reset, run on the server (works even if you forgot the password):
 *
 *   docker compose exec api node dist/seed/admin.js --email new@mail.com --password 'NewPass123'
 *   (local dev: npx ts-node prisma/admin.ts --email ... --password ...)
 *
 * --current <email>  which admin to change (default: ADMIN_EMAIL from .env, else the first admin)
 * --email <email>    new login email (optional)
 * --password <pw>    new password, at least 8 characters (optional)
 * Signs the admin out on every device.
 */
import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcryptjs';

const prisma = new PrismaClient();
const arg = (name: string) => {
  const i = process.argv.indexOf(`--${name}`);
  return i > -1 ? process.argv[i + 1] : undefined;
};

async function main() {
  const current = arg('current') ?? process.env.ADMIN_EMAIL;
  const email = arg('email')?.toLowerCase().trim();
  const password = arg('password');
  if (!email && !password) throw new Error('Pass --email and/or --password');
  if (password && password.length < 8) throw new Error('Password must be at least 8 characters');

  const admin =
    (current && (await prisma.user.findFirst({ where: { email: current.toLowerCase(), roles: { some: { role: 'ADMIN' } } } }))) ||
    (await prisma.user.findFirst({ where: { roles: { some: { role: 'ADMIN' } } }, orderBy: { createdAt: 'asc' } }));
  if (!admin) throw new Error('No admin found. Run the seed first.');
  if (email && (await prisma.user.findFirst({ where: { email, id: { not: admin.id } } }))) throw new Error(`${email} is used by another account`);

  await prisma.user.update({
    where: { id: admin.id },
    data: { ...(email ? { email } : {}), ...(password ? { passwordHash: await bcrypt.hash(password, 10) } : {}) },
  });
  await prisma.refreshToken.updateMany({ where: { userId: admin.id, revokedAt: null }, data: { revokedAt: new Date() } });
  console.log(`Admin updated: ${email ?? admin.email}${password ? ' (new password set)' : ''}`);
  if (email) console.log('Also change ADMIN_EMAIL in .env so the seed does not create a second admin.');
}

main()
  .catch((e) => { console.error(e.message); process.exitCode = 1; })
  .finally(() => prisma.$disconnect());
