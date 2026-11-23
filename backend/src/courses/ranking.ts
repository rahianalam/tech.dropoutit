/**
 * Course ranking used by search (see plan doc, section "Algorithms").
 *   S = 0.4 * textMatch + 0.25 * bayesRating/5 + 0.2 * popularity + 0.15 * freshness
 * Weights are a first guess and will be tuned with real data.
 */
export const PRIOR_RATING = 4.0;
export const PRIOR_WEIGHT = 10;

/** Bayesian average: few reviews pull the score toward the prior. */
export function bayesRating(avg: number, count: number): number {
  return (PRIOR_WEIGHT * PRIOR_RATING + avg * count) / (PRIOR_WEIGHT + count);
}

export function textMatch(query: string | undefined, title: string, subtitle?: string | null): number {
  if (!query) return 0;
  const q = query.toLowerCase().trim();
  const t = title.toLowerCase();
  if (t === q) return 1;
  if (t.startsWith(q)) return 0.9;
  if (t.includes(q)) return 0.75;
  const words = q.split(/\s+/).filter(Boolean);
  const hay = `${t} ${(subtitle ?? '').toLowerCase()}`;
  const hits = words.filter((w) => hay.includes(w)).length;
  return words.length ? (0.6 * hits) / words.length : 0;
}

export interface Rankable {
  title: string;
  subtitle?: string | null;
  ratingAvg: number;
  ratingCount: number;
  recentEnrollments: number;
  publishedAt: Date | null;
}

export function score(c: Rankable, query?: string, now = new Date()): number {
  const popularity = Math.min(1, Math.log1p(c.recentEnrollments) / Math.log1p(1000));
  const ageDays = c.publishedAt ? (now.getTime() - c.publishedAt.getTime()) / 864e5 : 365;
  const freshness = Math.exp(-ageDays / 90);
  return (
    0.4 * textMatch(query, c.title, c.subtitle) +
    0.25 * (bayesRating(c.ratingAvg, c.ratingCount) / 5) +
    0.2 * popularity +
    0.15 * freshness
  );
}
