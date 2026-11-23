import { bayesRating, score, textMatch } from '../src/courses/ranking';

describe('ranking', () => {
  it('Bayesian rating keeps a 2-review 5-star course below a 200-review 4.7 course', () => {
    expect(bayesRating(5, 2)).toBeLessThan(bayesRating(4.7, 200));
  });

  it('exact title match beats partial match', () => {
    expect(textMatch('flutter', 'Flutter')).toBeGreaterThan(textMatch('flutter', 'Learn Flutter fast'));
    expect(textMatch('react', 'Flutter basics')).toBe(0);
  });

  it('a matching course outranks a non-matching one with the same stats', () => {
    const base = { ratingAvg: 4.5, ratingCount: 50, recentEnrollments: 10, publishedAt: new Date() };
    expect(score({ ...base, title: 'Flutter basics' }, 'flutter')).toBeGreaterThan(score({ ...base, title: 'Excel basics' }, 'flutter'));
  });
});
