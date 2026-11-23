import { CanActivate, ExecutionContext, ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { IS_PUBLIC, ROLES } from './auth.decorators';

/**
 * Global guard: verifies the Bearer access token, loads the user's current
 * roles from the database (so an approval or block takes effect immediately),
 * then checks @Roles(). Public routes still get req.user when a valid token is sent.
 */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private reflector: Reflector,
    private jwt: JwtService,
    private prisma: PrismaService,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const targets = [ctx.getHandler(), ctx.getClass()];
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC, targets);
    const req = ctx.switchToHttp().getRequest();
    const header: string | undefined = req.headers.authorization;
    const token = header?.startsWith('Bearer ') ? header.slice(7) : undefined;

    if (token) {
      try {
        const payload = await this.jwt.verifyAsync<{ sub: string }>(token, {
          secret: process.env.JWT_ACCESS_SECRET,
        });
        const user = await this.prisma.user.findUnique({
          where: { id: payload.sub },
          include: { roles: true },
        });
        if (user && user.status === 'ACTIVE') {
          req.user = { id: user.id, roles: user.roles.map((r) => r.role) };
        }
      } catch {
        if (!isPublic) throw new UnauthorizedException('Invalid or expired token');
      }
    }

    if (isPublic) return true;
    if (!req.user) throw new UnauthorizedException();

    const required = this.reflector.getAllAndOverride<Role[]>(ROLES, targets);
    if (required?.length && !required.some((r) => req.user.roles.includes(r))) {
      throw new ForbiddenException('Missing role');
    }
    return true;
  }
}
