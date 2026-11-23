import { Injectable, Logger } from '@nestjs/common';
import { createSign } from 'crypto';
import { readFileSync } from 'fs';

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

export type SendResult = 'ok' | 'invalid-token' | 'error';

/**
 * Minimal Firebase Cloud Messaging (HTTP v1) client: signs a service-account JWT,
 * swaps it for an access token, and sends one message per device token.
 * Configure with FIREBASE_SERVICE_ACCOUNT (the JSON, raw or base64) or
 * FIREBASE_SERVICE_ACCOUNT_FILE (a path). Without either, push is off.
 */
@Injectable()
export class FcmClient {
  private log = new Logger('FCM');
  private account?: ServiceAccount | null;
  private token?: { value: string; exp: number };

  private load(): ServiceAccount | null {
    if (this.account !== undefined) return this.account;
    try {
      const raw = process.env.FIREBASE_SERVICE_ACCOUNT_FILE
        ? readFileSync(process.env.FIREBASE_SERVICE_ACCOUNT_FILE, 'utf8')
        : process.env.FIREBASE_SERVICE_ACCOUNT?.trim();
      if (!raw) return (this.account = null);
      const json = raw.startsWith('{') ? raw : Buffer.from(raw, 'base64').toString('utf8');
      const acc = JSON.parse(json) as ServiceAccount;
      if (!acc.project_id || !acc.client_email || !acc.private_key) throw new Error('missing fields');
      return (this.account = acc);
    } catch (e) {
      this.log.error(`Bad Firebase service account: ${(e as Error).message}`);
      return (this.account = null);
    }
  }

  get enabled() {
    return this.load() !== null;
  }

  private async accessToken(acc: ServiceAccount) {
    const now = Math.floor(Date.now() / 1000);
    if (this.token && this.token.exp - 60 > now) return this.token.value;
    const b64 = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url');
    const unsigned = `${b64({ alg: 'RS256', typ: 'JWT' })}.${b64({
      iss: acc.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    })}`;
    const signature = createSign('RSA-SHA256').update(unsigned).sign(acc.private_key, 'base64url');
    const res = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${signature}` }),
    });
    if (!res.ok) throw new Error(`token ${res.status} ${await res.text()}`);
    const body = (await res.json()) as { access_token: string; expires_in: number };
    this.token = { value: body.access_token, exp: now + body.expires_in };
    return body.access_token;
  }

  async send(deviceToken: string, title: string, body: string, data: Record<string, string> = {}): Promise<SendResult> {
    const acc = this.load();
    if (!acc) return 'error';
    try {
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${acc.project_id}/messages:send`, {
        method: 'POST',
        headers: { authorization: `Bearer ${await this.accessToken(acc)}`, 'content-type': 'application/json' },
        body: JSON.stringify({
          message: {
            token: deviceToken,
            notification: { title, body },
            data,
            android: { priority: 'HIGH' },
            apns: { payload: { aps: { sound: 'default' } } },
          },
        }),
      });
      if (res.ok) return 'ok';
      const text = await res.text();
      // The phone uninstalled the app or the token rotated: forget it.
      if (res.status === 404 || text.includes('UNREGISTERED') || (res.status === 400 && text.includes('registration token'))) return 'invalid-token';
      this.log.warn(`send ${res.status} ${text.slice(0, 300)}`);
      return 'error';
    } catch (e) {
      this.log.warn(`send failed: ${(e as Error).message}`);
      return 'error';
    }
  }
}
