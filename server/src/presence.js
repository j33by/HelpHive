import { query } from './db.js';

/**
 * Lightweight usage tracking for the admin dashboard. It stores who was active
 * in which hour, never what they did. Writes are throttled in memory so a busy
 * person costs at most one row per hour and one update every two minutes.
 */
const seen = new Map(); // userId -> { hour, wrote }

export function trackPresence(req, _res, next) {
  next();
  const id = req.user?.id;
  if (!id) return;
  const now = Date.now();
  const hour = Math.floor(now / 3_600_000);
  const prev = seen.get(id);
  if (prev && prev.hour === hour && now - prev.wrote < 120_000) return;
  seen.set(id, { hour, wrote: now });
  if (seen.size > 20000) seen.clear();

  const tasks = [
    query('insert into user_presence (user_id, last_seen_at) values ($1, now()) on conflict (user_id) do update set last_seen_at = now()', [id]),
  ];
  if (!prev || prev.hour !== hour) {
    tasks.push(query("insert into active_hourly (user_id, hour) values ($1, date_trunc('hour', now())) on conflict do nothing", [id]));
  }
  Promise.all(tasks).catch((err) => console.error('presence write failed:', err.message));
}

/** One login per person per 30 minutes, counted when the app reports a fresh launch. */
export async function recordLogin(userId, platform) {
  const { rows } = await query(
    "select 1 from login_events where user_id = $1 and created_at > now() - interval '30 minutes' limit 1",
    [userId],
  );
  if (rows.length) return;
  await query('insert into login_events (user_id, platform) values ($1, $2)', [userId, platform ?? null]);
  await query(
    `insert into user_presence (user_id, last_seen_at, last_login_at, login_count) values ($1, now(), now(), 1)
     on conflict (user_id) do update set last_login_at = now(), login_count = user_presence.login_count + 1, last_seen_at = now()`,
    [userId],
  );
}
