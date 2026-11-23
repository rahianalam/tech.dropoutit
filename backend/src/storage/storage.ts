import { Global, Injectable, Logger, Module } from '@nestjs/common';
import { createReadStream, existsSync, mkdirSync, renameSync, copyFileSync, rmSync, statSync, writeFileSync } from 'fs';
import { dirname, join, resolve } from 'path';
import type { Readable } from 'stream';

/**
 * Where uploaded bytes (CVs, logos, thumbnails, lesson videos) are kept.
 *
 * The rest of the app only talks to this interface, so moving videos to
 * Firebase Storage, S3, Cloudflare R2 or Bunny later means writing one class
 * that implements it and setting STORAGE_DRIVER — no other code changes.
 * See docs/STORAGE.md.
 */
export interface StorageDriver {
  readonly name: string;
  /** Store a file that is already on local disk (multer writes big uploads to a temp file). */
  putFile(key: string, localPath: string, mime: string): Promise<void>;
  /** Store bytes held in memory (small uploads). */
  putBuffer(key: string, data: Buffer, mime: string): Promise<void>;
  /** Size in bytes, or null when the key does not exist. */
  size(key: string): Promise<number | null>;
  /** Read the whole file or an inclusive byte range (for video seeking). */
  read(key: string, range?: { start: number; end: number }): Promise<Readable>;
  remove(key: string): Promise<void>;
  /**
   * Optional: a direct, expiring URL from the storage provider itself
   * (e.g. a Firebase/S3 signed URL). When present the app streams from the
   * provider and our server is not in the video path. Local disk returns null.
   */
  directUrl?(key: string, ttlSeconds: number): Promise<string | null>;
}

/** Default driver: a folder on the server (a Docker volume in production). */
export class LocalDiskDriver implements StorageDriver {
  readonly name = 'local';
  constructor(private root: string) {
    if (!existsSync(root)) mkdirSync(root, { recursive: true });
  }
  private path(key: string) {
    const p = resolve(this.root, key);
    if (!p.startsWith(resolve(this.root))) throw new Error('Bad storage key');
    return p;
  }
  async putFile(key: string, localPath: string) {
    const dest = this.path(key);
    mkdirSync(dirname(dest), { recursive: true });
    try {
      renameSync(localPath, dest);
    } catch {
      // temp dir on another disk: copy instead of move
      copyFileSync(localPath, dest);
      rmSync(localPath, { force: true });
    }
  }
  async putBuffer(key: string, data: Buffer) {
    const dest = this.path(key);
    mkdirSync(dirname(dest), { recursive: true });
    writeFileSync(dest, data);
  }
  async size(key: string) {
    const p = this.path(key);
    return existsSync(p) ? statSync(p).size : null;
  }
  async read(key: string, range?: { start: number; end: number }) {
    return createReadStream(this.path(key), range);
  }
  async remove(key: string) {
    rmSync(this.path(key), { force: true });
  }
}

/**
 * Placeholder for a cloud provider. To switch to Firebase Storage:
 *   1. npm i firebase-admin
 *   2. implement the methods below with bucket.file(key).save / createReadStream / getSignedUrl
 *   3. set STORAGE_DRIVER=firebase and FIREBASE_STORAGE_BUCKET in .env
 * Until then the server refuses to start with this driver, so nothing is silently lost.
 */
export class NotConfiguredDriver implements StorageDriver {
  constructor(readonly name: string) {}
  private fail(): never {
    throw new Error(`STORAGE_DRIVER=${this.name} is not implemented yet — see docs/STORAGE.md`);
  }
  putFile(): Promise<void> { this.fail(); }
  putBuffer(): Promise<void> { this.fail(); }
  size(): Promise<number | null> { this.fail(); }
  read(): Promise<Readable> { this.fail(); }
  remove(): Promise<void> { this.fail(); }
}

export function createDriver(env = process.env): StorageDriver {
  const kind = (env.STORAGE_DRIVER ?? 'local').toLowerCase();
  if (kind === 'local') return new LocalDiskDriver(env.UPLOAD_DIR ?? join(process.cwd(), 'uploads'));
  if (env.NODE_ENV === 'production') new NotConfiguredDriver(kind).putBuffer();
  new Logger('Storage').warn(`STORAGE_DRIVER=${kind} is not implemented; uploads will fail`);
  return new NotConfiguredDriver(kind);
}

@Injectable()
export class StorageService {
  readonly driver: StorageDriver = createDriver();
}

@Global()
@Module({ providers: [StorageService], exports: [StorageService] })
export class StorageModule {}
