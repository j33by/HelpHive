import { query } from './db.js';

/**
 * Helpful-star badges. A badge is earned by reaching a star total; the app
 * keeps the names, quotes and artwork (app/lib/badges.dart), the server only
 * needs the thresholds so it can tell every client which badge someone wears.
 * Keep the two lists in step.
 */
export const TIERS = [
  { key: 'fresh_buzz', min: 1 },
  { key: 'helping_wing', min: 3 },
  { key: 'worker_bee', min: 5 },
  { key: 'honey_maker', min: 10 },
  { key: 'hive_guardian', min: 25 },
  { key: 'nectar_hero', min: 50 },
  { key: 'queen_bee', min: 100 },
];

export function badgeKey(stars) {
  let key = null;
  for (const t of TIERS) if (stars >= t.min) key = t.key;
  return key;
}

/** id -> number of helpful stars, for every id given (0 when none). */
export async function loadStars(ids) {
  const wanted = [...new Set(ids.filter(Boolean))];
  const out = new Map(wanted.map((id) => [id, 0]));
  if (!wanted.length) return out;
  const { rows } = await query(
    `select user_id, count(*)::int as n
       from comments
      where is_helpful and user_id = any($1::uuid[])
      group by user_id`,
    [wanted],
  );
  for (const r of rows) out.set(r.user_id, r.n);
  return out;
}

/** Copy of a loadProfiles() map where every user also carries { stars, badge }. */
export async function withStars(users) {
  const stars = await loadStars([...users.keys()]);
  const out = new Map();
  for (const [id, u] of users) {
    const n = stars.get(id) ?? 0;
    out.set(id, { ...u, stars: n, badge: badgeKey(n) });
  }
  return out;
}
