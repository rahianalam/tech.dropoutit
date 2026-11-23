import { Injectable } from '@nestjs/common';
import { createHash } from 'crypto';

/**
 * Turns a private storage key into a short-lived URL, so a shared link stops
 * working after it expires. Uses Bunny CDN token authentication
 * (sha256(securityKey + path + expires), base64url) — swap here if the video host changes.
 */
@Injectable()
export class MediaService {
  sign(key: string, ttlSeconds = 2 * 3600): string {
    const base = process.env.MEDIA_BASE_URL ?? 'https://media.tech.dropout.it';
    const secret = process.env.MEDIA_SIGNING_KEY ?? 'dev-media-key';
    const path = `/${key.replace(/^\/+/, '')}`;
    const expires = Math.floor(Date.now() / 1000) + ttlSeconds;
    const token = createHash('sha256').update(secret + path + expires).digest('base64url');
    return `${base}${path}?token=${token}&expires=${expires}`;
  }
}
