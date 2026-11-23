import {
  BadRequestException, Controller, ForbiddenException, Get, Injectable, Module, NotFoundException, Param, ParseUUIDPipe,
  Post, Query, Res, UploadedFile, UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { UploadKind } from '@prisma/client';
import { createHmac, timingSafeEqual } from 'crypto';
import type { Response } from 'express';
import { createReadStream, existsSync, mkdirSync, writeFileSync } from 'fs';
import { join } from 'path';
import { AuthUser, CurrentUser, Public } from '../common/auth.decorators';
import { PrismaService } from '../prisma/prisma.service';

const MAX_BYTES = 5 * 1024 * 1024;
const ALLOWED: Record<UploadKind, string[]> = {
  CV: ['application/pdf'],
  LOGO: ['image/png', 'image/jpeg', 'image/webp'],
};
/** Check the file's first bytes too, so a renamed .exe is not stored as a PDF. */
const MAGIC: Record<string, (b: Buffer) => boolean> = {
  'application/pdf': (b) => b.subarray(0, 5).toString('latin1') === '%PDF-',
  'image/png': (b) => b.subarray(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47])),
  'image/jpeg': (b) => b[0] === 0xff && b[1] === 0xd8,
  'image/webp': (b) => b.subarray(8, 12).toString('latin1') === 'WEBP',
};

/**
 * Files live on the server disk (a Docker volume in production) and are never
 * public: the API hands out links signed with HMAC that expire, and only to
 * people allowed to see the file.
 */
@Injectable()
export class UploadsService {
  constructor(private prisma: PrismaService) {}

  private get dir() {
    const d = process.env.UPLOAD_DIR ?? join(process.cwd(), 'uploads');
    if (!existsSync(d)) mkdirSync(d, { recursive: true });
    return d;
  }
  private secret() { return process.env.FILE_SIGNING_KEY ?? process.env.JWT_ACCESS_SECRET ?? 'dev-file-key'; }
  private sig(id: string, exp: number) { return createHmac('sha256', this.secret()).update(`${id}.${exp}`).digest('base64url'); }

  async save(owner: string, kind: UploadKind, file?: Express.Multer.File) {
    if (!file) throw new BadRequestException('No file');
    if (file.size > MAX_BYTES) throw new BadRequestException('File is larger than 5 MB');
    if (!ALLOWED[kind].includes(file.mimetype) || !MAGIC[file.mimetype](file.buffer)) {
      throw new BadRequestException(kind === 'CV' ? 'CV must be a PDF' : 'Logo must be PNG, JPG or WebP');
    }
    const up = await this.prisma.upload.create({
      data: { ownerId: owner, kind, mime: file.mimetype, size: file.size, originalName: file.originalname.slice(0, 200) },
    });
    writeFileSync(join(this.dir, up.id), file.buffer);
    return { id: up.id, originalName: up.originalName, size: up.size, url: this.link(up.id) };
  }

  /** Short-lived link the app can open in a browser or PDF viewer (no auth header needed). */
  link(id: string, ttlSeconds = 15 * 60) {
    const exp = Math.floor(Date.now() / 1000) + ttlSeconds;
    const base = process.env.PUBLIC_API_URL ?? 'http://localhost:3000';
    return `${base}/api/v1/files/${id}?exp=${exp}&sig=${this.sig(id, exp)}`;
  }

  async open(id: string, exp: string, sig: string) {
    const e = Number(exp);
    const want = Buffer.from(this.sig(id, e));
    const got = Buffer.from(sig ?? '');
    if (!e || e < Date.now() / 1000 || want.length !== got.length || !timingSafeEqual(want, got)) {
      throw new ForbiddenException('Link expired');
    }
    const up = await this.prisma.upload.findUnique({ where: { id } });
    const path = join(this.dir, id);
    if (!up || !existsSync(path)) throw new NotFoundException();
    return { up, stream: createReadStream(path) };
  }
}

@Controller()
export class UploadsController {
  constructor(private uploads: UploadsService) {}

  @Post('uploads')
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_BYTES + 1 } }))
  upload(@CurrentUser() u: AuthUser, @UploadedFile() file: Express.Multer.File, @Query('kind') kind: string) {
    if (!['CV', 'LOGO'].includes(kind)) throw new BadRequestException('kind must be CV or LOGO');
    return this.uploads.save(u.id, kind as UploadKind, file);
  }

  @Public() @Get('files/:id')
  async file(@Param('id', ParseUUIDPipe) id: string, @Query('exp') exp: string, @Query('sig') sig: string, @Res() res: Response) {
    const { up, stream } = await this.uploads.open(id, exp, sig);
    res.setHeader('Content-Type', up.mime);
    res.setHeader('Content-Disposition', `inline; filename="${encodeURIComponent(up.originalName)}"`);
    res.setHeader('Cache-Control', 'private, no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    stream.pipe(res);
  }
}

@Module({ controllers: [UploadsController], providers: [UploadsService], exports: [UploadsService] })
export class UploadsModule {}
