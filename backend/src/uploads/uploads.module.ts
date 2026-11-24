import {
  BadRequestException, Controller, ForbiddenException, Get, Headers, Injectable, Module, NotFoundException, Param, ParseUUIDPipe,
  Post, Query, Res, UploadedFile, UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { UploadKind } from '@prisma/client';
import { createHmac, timingSafeEqual } from 'crypto';
import type { Response } from 'express';
import { closeSync, openSync, readSync, rmSync } from 'fs';
import { diskStorage } from 'multer';
import { tmpdir } from 'os';
import { AuthUser, CurrentUser, Public } from '../common/auth.decorators';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage';

const MAX_BYTES = 5 * 1024 * 1024;
/** Lesson videos: 2 GB by default, change with MAX_VIDEO_MB. */
export const maxVideoBytes = () => Number(process.env.MAX_VIDEO_MB ?? 2000) * 1024 * 1024;

const ALLOWED: Record<Exclude<UploadKind, 'VIDEO'>, string[]> = {
  CV: ['application/pdf'],
  LOGO: ['image/png', 'image/jpeg', 'image/webp'],
  IMAGE: ['image/png', 'image/jpeg', 'image/webp'],
};
const VIDEO_MIME = ['video/mp4', 'video/webm', 'video/quicktime', 'video/x-matroska'];

/** Check the file's first bytes too, so a renamed .exe is not stored as a PDF. */
const MAGIC: Record<string, (b: Buffer) => boolean> = {
  'application/pdf': (b) => b.subarray(0, 5).toString('latin1') === '%PDF-',
  'image/png': (b) => b.subarray(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47])),
  'image/jpeg': (b) => b[0] === 0xff && b[1] === 0xd8,
  'image/webp': (b) => b.subarray(8, 12).toString('latin1') === 'WEBP',
};
/** mp4/mov have "ftyp" at byte 4; webm/mkv start with the EBML header. Returns the real type or null. */
function sniffVideo(b: Buffer): string | null {
  if (b.subarray(4, 8).toString('latin1') === 'ftyp') {
    return b.subarray(8, 10).toString('latin1') === 'qt' ? 'video/quicktime' : 'video/mp4';
  }
  if (b.subarray(0, 4).equals(Buffer.from([0x1a, 0x45, 0xdf, 0xa3]))) return 'video/webm';
  return null;
}

/**
 * Files are stored through the StorageService (local disk today, Firebase/S3 later) and are never
 * listed publicly. CVs and videos are served through HMAC-signed links that expire, and only to people
 * allowed to see them; course images get a permanent public link.
 */
@Injectable()
export class UploadsService {
  constructor(private prisma: PrismaService, private storage: StorageService) {}

  private secret() { return process.env.FILE_SIGNING_KEY ?? process.env.JWT_ACCESS_SECRET ?? 'dev-file-key'; }
  private sig(id: string, exp: number) { return createHmac('sha256', this.secret()).update(`${id}.${exp}`).digest('base64url'); }
  private base() {
    // PUBLIC_API_URL already ends in /api/v1 (same value the payment callbacks use)
    return (process.env.PUBLIC_API_URL ?? 'http://localhost:3000/api/v1').replace(/\/+$/, '');
  }
  private key(up: { id: string; storageKey: string | null }) { return up.storageKey ?? up.id; }

  async save(owner: string, kind: Exclude<UploadKind, 'VIDEO'>, file?: Express.Multer.File) {
    if (!file) throw new BadRequestException('No file');
    if (file.size > MAX_BYTES) throw new BadRequestException('File is larger than 5 MB');
    if (!ALLOWED[kind].includes(file.mimetype) || !MAGIC[file.mimetype](file.buffer)) {
      throw new BadRequestException(kind === 'CV' ? 'CV must be a PDF' : 'Image must be PNG, JPG or WebP');
    }
    const up = await this.prisma.upload.create({
      data: { ownerId: owner, kind, mime: file.mimetype, size: file.size, originalName: file.originalname.slice(0, 200) },
    });
    const storageKey = `${kind.toLowerCase()}/${up.id}`;
    await this.storage.driver.putBuffer(storageKey, file.buffer, file.mimetype);
    await this.prisma.upload.update({ where: { id: up.id }, data: { storageKey } });
    return { id: up.id, originalName: up.originalName, size: up.size, url: kind === 'IMAGE' ? this.publicUrl(up.id) : this.link(up.id) };
  }

  /** A lesson video that multer has written to a temp file. Moves it into storage. */
  async saveVideo(owner: string, file?: Express.Multer.File) {
    if (!file) throw new BadRequestException('No file');
    const drop = () => rmSync(file.path, { force: true });
    if (file.size > maxVideoBytes()) { drop(); throw new BadRequestException(`Video is larger than ${process.env.MAX_VIDEO_MB ?? 2000} MB`); }
    const head = Buffer.alloc(16);
    const fd = openSync(file.path, 'r');
    readSync(fd, head, 0, 16, 0);
    closeSync(fd);
    const mime = sniffVideo(head);
    if (!mime) { drop(); throw new BadRequestException('Video must be MP4, MOV or WebM'); }
    const up = await this.prisma.upload.create({
      data: { ownerId: owner, kind: 'VIDEO', mime, size: file.size, originalName: file.originalname.slice(0, 200) },
    });
    const storageKey = `video/${up.id}`;
    try {
      await this.storage.driver.putFile(storageKey, file.path, mime);
    } catch (e) {
      drop();
      await this.prisma.upload.delete({ where: { id: up.id } });
      throw e;
    }
    return this.prisma.upload.update({ where: { id: up.id }, data: { storageKey } });
  }

  async removeFile(up: { id: string; storageKey?: string | null }) {
    await this.storage.driver.remove(this.key({ id: up.id, storageKey: up.storageKey ?? null }));
  }

  async remove(id: string) {
    const up = await this.prisma.upload.findUnique({ where: { id } });
    if (!up) return;
    await this.removeFile(up);
    await this.prisma.upload.delete({ where: { id } });
  }

  /** Short-lived link the app can open in a browser, PDF viewer or video player (no auth header needed). */
  link(id: string, ttlSeconds = 15 * 60) {
    const exp = Math.floor(Date.now() / 1000) + ttlSeconds;
    return `${this.base()}/files/${id}?exp=${exp}&sig=${this.sig(id, exp)}`;
  }

  publicUrl(id: string) { return `${this.base()}/images/${id}`; }

  verify(id: string, exp: string, sig: string) {
    const e = Number(exp);
    const want = Buffer.from(this.sig(id, e));
    const got = Buffer.from(sig ?? '');
    if (!e || e < Date.now() / 1000 || want.length !== got.length || !timingSafeEqual(want, got)) {
      throw new ForbiddenException('Link expired');
    }
  }

  /** Streams a file, honouring HTTP Range so video players can seek without downloading everything. */
  async send(id: string, res: Response, range: string | undefined, opts: { publicOnly?: boolean } = {}) {
    const up = await this.prisma.upload.findUnique({ where: { id } });
    if (!up || (opts.publicOnly && up.kind !== 'IMAGE')) throw new NotFoundException();
    const key = this.key(up);
    const driver = this.storage.driver;
    if (driver.directUrl) {
      const url = await driver.directUrl(key, 2 * 3600);
      if (url) return res.redirect(302, url);
    }
    const size = await driver.size(key);
    if (size === null) throw new NotFoundException();
    res.setHeader('Content-Type', up.mime);
    res.setHeader('Accept-Ranges', 'bytes');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Cache-Control', opts.publicOnly ? 'public, max-age=31536000, immutable' : 'private, no-store');
    if (up.kind !== 'VIDEO' && up.kind !== 'IMAGE') {
      res.setHeader('Content-Disposition', `inline; filename="${encodeURIComponent(up.originalName)}"`);
    }
    const m = range && /^bytes=(\d*)-(\d*)$/.exec(range.trim());
    if (m && (m[1] || m[2])) {
      let start = m[1] ? Number(m[1]) : size - Number(m[2]);
      let end = m[1] && m[2] ? Number(m[2]) : size - 1;
      if (start < 0) start = 0;
      if (end >= size) end = size - 1;
      if (start > end || start >= size) {
        res.status(416).setHeader('Content-Range', `bytes */${size}`);
        return res.end();
      }
      res.status(206);
      res.setHeader('Content-Range', `bytes ${start}-${end}/${size}`);
      res.setHeader('Content-Length', String(end - start + 1));
      (await driver.read(key, { start, end })).pipe(res);
      return;
    }
    res.setHeader('Content-Length', String(size));
    (await driver.read(key)).pipe(res);
  }
}

@Controller()
export class UploadsController {
  constructor(private uploads: UploadsService) {}

  @Post('uploads')
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_BYTES + 1 } }))
  upload(@CurrentUser() u: AuthUser, @UploadedFile() file: Express.Multer.File, @Query('kind') kind: string) {
    if (!['CV', 'LOGO', 'IMAGE'].includes(kind)) throw new BadRequestException('kind must be CV, LOGO or IMAGE');
    return this.uploads.save(u.id, kind as 'CV' | 'LOGO' | 'IMAGE', file);
  }

  @Public() @Get('files/:id')
  async file(
    @Param('id', ParseUUIDPipe) id: string, @Query('exp') exp: string, @Query('sig') sig: string,
    @Headers('range') range: string | undefined, @Res() res: Response,
  ) {
    this.uploads.verify(id, exp, sig);
    await this.uploads.send(id, res, range);
  }

  /** Course thumbnails and other images meant to be public. */
  @Public() @Get('images/:id')
  async image(@Param('id', ParseUUIDPipe) id: string, @Headers('range') range: string | undefined, @Res() res: Response) {
    await this.uploads.send(id, res, range, { publicOnly: true });
  }
}

/** Multer options for big video uploads: written to a temp file, never held in memory. */
export const videoUploadOptions = () => ({
  storage: diskStorage({ destination: process.env.UPLOAD_TMP_DIR ?? tmpdir() }),
  limits: { fileSize: maxVideoBytes() + 1 },
});

@Module({ controllers: [UploadsController], providers: [UploadsService], exports: [UploadsService] })
export class UploadsModule {}
