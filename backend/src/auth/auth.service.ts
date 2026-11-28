import { ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
import { createHash, randomBytes } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { LoginDto, RegisterDto } from './auth.dto';

const REFRESH_DAYS = 30;

export function normalizePhone(phone?: string | null): string | undefined {
  if (!phone) return undefined;
  const digits = phone.replace(/\D/g, '');
  return digits.startsWith('880') ? `+${digits}` : `+88${digits}`;
}

const sha256 = (s: string) => createHash('sha256').update(s).digest('hex');

@Injectable()
export class AuthService {
  constructor(
    private prisma: PrismaService,
    private jwt: JwtService,
  ) {}

  async register(dto: RegisterDto) {
    const email = dto.email?.toLowerCase().trim();
    const phone = normalizePhone(dto.phone);
    const existing = await this.prisma.user.findFirst({
      where: { OR: [email ? { email } : {}, phone ? { phone } : {}].filter((c) => Object.keys(c).length) },
    });
    if (existing) throw new ConflictException('An account with this email or phone already exists');

    const referrer = dto.ref ? await this.prisma.user.findUnique({ where: { referralCode: dto.ref.trim().toUpperCase() } }) : null;
    // Everyone starts as a student; teacher/employer roles are added later.
    const user = await this.prisma.user.create({
      data: {
        referredById: referrer?.id,
        name: dto.name.trim(),
        email,
        phone,
        passwordHash: await bcrypt.hash(dto.password, 10),
        roles: { create: [{ role: 'STUDENT' }, { role: 'JOB_SEEKER' }] },
      },
    });
    return this.issueTokens(user.id);
  }

  async login(dto: LoginDto) {
    const id = dto.identifier.trim();
    const user = await this.prisma.user.findFirst({
      where: id.includes('@') ? { email: id.toLowerCase() } : { phone: normalizePhone(id) },
    });
    if (!user || !(await bcrypt.compare(dto.password, user.passwordHash))) {
      throw new UnauthorizedException('Wrong email/phone or password');
    }
    if (user.status !== 'ACTIVE') throw new UnauthorizedException('Account is blocked');
    return this.issueTokens(user.id);
  }

  /** Rotates the refresh token: the old one is revoked, a new pair is issued. */
  async refresh(refreshToken: string) {
    const [id, secret] = refreshToken.split('.');
    const stored = id && secret ? await this.prisma.refreshToken.findUnique({ where: { id } }) : null;
    if (!stored || stored.revokedAt || stored.expiresAt < new Date() || stored.tokenHash !== sha256(secret)) {
      throw new UnauthorizedException('Invalid refresh token');
    }
    // Only one caller can spend a refresh token, even if two requests race with it.
    const spent = await this.prisma.refreshToken.updateMany({ where: { id, revokedAt: null }, data: { revokedAt: new Date() } });
    if (spent.count === 0) throw new UnauthorizedException('Invalid refresh token');
    // A blocked account gets no new tokens (otherwise the app would refresh and retry forever).
    const user = await this.prisma.user.findUnique({ where: { id: stored.userId }, select: { status: true } });
    if (!user || user.status !== 'ACTIVE') throw new UnauthorizedException('Account is blocked');
    return this.issueTokens(stored.userId);
  }

  async logout(refreshToken: string) {
    const [id] = refreshToken.split('.');
    if (id) await this.prisma.refreshToken.updateMany({ where: { id, revokedAt: null }, data: { revokedAt: new Date() } });
  }

  /**
   * Change password (current password required). Every other signed-in device is logged out;
   * the caller gets a fresh token pair so this device stays signed in.
   */
  async changePassword(userId: string, current: string, next: string) {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    if (!(await bcrypt.compare(current, user.passwordHash))) throw new UnauthorizedException('Current password is wrong');
    await this.prisma.user.update({ where: { id: userId }, data: { passwordHash: await bcrypt.hash(next, 10) } });
    await this.prisma.refreshToken.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: new Date() } });
    await this.prisma.auditLog.create({ data: { actorId: userId, action: 'user.change_password', target: userId } });
    return this.issueTokens(userId);
  }

  /** Change the email and/or phone used to sign in (password required). */
  async changeLogin(userId: string, password: string, email?: string, phone?: string) {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    if (!(await bcrypt.compare(password, user.passwordHash))) throw new UnauthorizedException('Password is wrong');
    const data: { email?: string; phone?: string } = {};
    if (email) data.email = email.toLowerCase().trim();
    if (phone) data.phone = normalizePhone(phone);
    const taken = await this.prisma.user.findFirst({
      where: { id: { not: userId }, OR: [data.email ? { email: data.email } : {}, data.phone ? { phone: data.phone } : {}].filter((c) => Object.keys(c).length) },
    });
    if (taken) throw new ConflictException('Another account already uses this email or phone');
    await this.prisma.user.update({ where: { id: userId }, data });
    await this.prisma.auditLog.create({ data: { actorId: userId, action: 'user.change_login', target: userId, meta: data } });
  }

  private async issueTokens(userId: string) {
    const accessToken = await this.jwt.signAsync(
      { sub: userId },
      { secret: process.env.JWT_ACCESS_SECRET, expiresIn: '15m' },
    );
    const secret = randomBytes(32).toString('hex');
    const row = await this.prisma.refreshToken.create({
      data: {
        userId,
        tokenHash: sha256(secret),
        expiresAt: new Date(Date.now() + REFRESH_DAYS * 864e5),
      },
    });
    return { accessToken, refreshToken: `${row.id}.${secret}` };
  }
}
