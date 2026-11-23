/**
 * Slot generation (plan doc, algorithm E). Pure functions so they are easy to test.
 * Rules are in the teacher's local time; Bangladesh is UTC+6 with no DST, and the
 * offset table can grow if teachers in other zones join.
 */
export const OFFSETS_MIN: Record<string, number> = { 'Asia/Dhaka': 360 };
export const MIN_LEAD_MINUTES = 120; // students can't book a slot starting within 2 hours
export const HOLD_MINUTES = 10;

export interface Rule {
  weekday: number; // 0 = Sunday, in the teacher's zone
  startMinute: number;
  endMinute: number;
  slotMinutes: number;
  pricePaisa: number;
  timezone: string;
}

export interface Slot {
  startAt: Date;
  endAt: Date;
  pricePaisa: number;
}

export function generateSlots(rules: Rule[], taken: Date[], from: Date, days: number, now = new Date()): Slot[] {
  const takenSet = new Set(taken.map((d) => d.getTime()));
  const earliest = now.getTime() + MIN_LEAD_MINUTES * 60_000;
  const out: Slot[] = [];
  for (const rule of rules) {
    const offset = (OFFSETS_MIN[rule.timezone] ?? 360) * 60_000;
    // midnight of `from` in the teacher's zone, expressed in UTC
    const localFrom = new Date(from.getTime() + offset);
    const day0 = Date.UTC(localFrom.getUTCFullYear(), localFrom.getUTCMonth(), localFrom.getUTCDate()) - offset;
    for (let d = 0; d < days; d++) {
      const dayStart = day0 + d * 864e5;
      if (new Date(dayStart + offset).getUTCDay() !== rule.weekday) continue;
      for (let m = rule.startMinute; m + rule.slotMinutes <= rule.endMinute; m += rule.slotMinutes) {
        const start = dayStart + m * 60_000;
        if (start < earliest || takenSet.has(start)) continue;
        out.push({ startAt: new Date(start), endAt: new Date(start + rule.slotMinutes * 60_000), pricePaisa: rule.pricePaisa });
      }
    }
  }
  return out.sort((a, b) => a.startAt.getTime() - b.startAt.getTime());
}

export function overlaps(a: Pick<Rule, 'weekday' | 'startMinute' | 'endMinute'>, b: Pick<Rule, 'weekday' | 'startMinute' | 'endMinute'>) {
  return a.weekday === b.weekday && a.startMinute < b.endMinute && b.startMinute < a.endMinute;
}

/** A private video-call room (Jitsi by default; swap the base URL for a self-hosted server). */
export function meetingUrl(): string {
  const base = process.env.MEETING_BASE_URL ?? 'https://meet.jit.si';
  const id = require('crypto').randomBytes(9).toString('base64url');
  return `${base}/techdropout-${id}`;
}
