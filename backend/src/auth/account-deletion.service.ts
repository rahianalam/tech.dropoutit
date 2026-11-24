import { UploadKind } from '@prisma/client';
import { ConflictException, ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { randomBytes } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { UploadsService } from '../uploads/uploads.module';

/**
 * Self-service account deletion (required by Google Play and the App Store).
 * Personal data is wiped; orders, payments and ledger rows stay (they are
 * needed for accounting and refunds) but point to an anonymous user.
 */
@Injectable()
export class AccountDeletionService {
  constructor(private prisma: PrismaService, private uploads: UploadsService) {}

  async delete(userId: string, password: string) {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId }, include: { roles: true } });
    if (!(await bcrypt.compare(password, user.passwordHash))) throw new UnauthorizedException('Wrong password');
    if (user.roles.some((r) => r.role === 'ADMIN')) throw new ForbiddenException('An admin account cannot be deleted from the app');

    const owed = await this.prisma.ledgerEntry.aggregate({ where: { teacherId: userId, status: { in: ['PENDING', 'AVAILABLE'] } }, _sum: { amountPaisa: true } });
    if ((owed._sum.amountPaisa ?? 0) > 0) throw new ConflictException('You still have unpaid earnings. Please wait for your payout, then delete the account.');
    const upcoming = await this.prisma.booking.count({
      where: { status: { in: ['HELD', 'CONFIRMED'] }, endAt: { gt: new Date() }, OR: [{ teacherId: userId }, { studentId: userId }] },
    });
    if (upcoming > 0) throw new ConflictException('You have upcoming sessions. Cancel or finish them first.');

    // Personal files go; course videos and thumbnails stay, because enrolled students keep access.
    const personal = { ownerId: userId, kind: { in: ['CV', 'LOGO'] as UploadKind[] } };
    const files = await this.prisma.upload.findMany({ where: personal, select: { id: true, storageKey: true } });
    await this.prisma.$transaction([
      this.prisma.user.update({
        where: { id: userId },
        data: {
          name: 'মুছে ফেলা অ্যাকাউন্ট',
          email: null,
          phone: null,
          avatarUrl: null,
          passwordHash: await bcrypt.hash(randomBytes(32).toString('hex'), 10),
          status: 'DELETED',
        },
      }),
      this.prisma.refreshToken.deleteMany({ where: { userId } }),
      this.prisma.deviceToken.deleteMany({ where: { userId } }),
      this.prisma.notification.deleteMany({ where: { userId } }),
      this.prisma.portfolioItem.deleteMany({ where: { ownerId: userId } }),
      this.prisma.teacherApplication.deleteMany({ where: { userId } }),
      this.prisma.seekerProfile.deleteMany({ where: { userId } }),
      this.prisma.availabilityRule.deleteMany({ where: { teacherId: userId } }),
      this.prisma.teacherProfile.updateMany({ where: { userId }, data: { payoutMethod: null, payoutAccount: null } }),
      // Hide their courses and jobs from everyone new; enrolled students keep access.
      this.prisma.course.updateMany({ where: { teacherId: userId, status: { in: ['PUBLISHED', 'IN_REVIEW'] } }, data: { status: 'DRAFT' } }),
      this.prisma.job.updateMany({ where: { employerId: userId, status: { in: ['LIVE', 'PENDING'] } }, data: { status: 'CLOSED' } }),
      this.prisma.upload.deleteMany({ where: personal }),
      this.prisma.userRole.deleteMany({ where: { userId } }),
      this.prisma.auditLog.create({ data: { actorId: userId, action: 'user.delete_self', target: userId } }),
    ]);
    for (const f of files) await this.uploads.removeFile(f);
  }
}
