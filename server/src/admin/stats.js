import { query } from '../db.js';
import { admin as sb } from '../supabase.js';

/**
 * Dashboard numbers. Everything here is an aggregate: counts per hour or day.
 * Message *content* is never read; messages are only counted.
 */
const HOUR = 3_600_000;
const DAY = 24 * HOUR;

export function resolveRange({ range, from, to }) {
  const end = to ? new Date(to) : new Date();
  let start;
  if (from) start = new Date(from);
  else {
    const days = { '24h': 1, '7d': 7, '30d': 30, '90d': 90, '1y': 365 }[range] ?? 7;
    start = new Date(end.getTime() - days * DAY);
  }
  if (!(start < end)) throw new Error('bad range');
  const span = end - start;
  const unit = span <= 3 * DAY ? 'hour' : 'day';
  // align to bucket edges so the first and last bars are whole
  const step = unit === 'hour' ? HOUR : DAY;
  const s = new Date(Math.floor(start.getTime() / step) * step);
  const e = new Date(Math.ceil(end.getTime() / step) * step);
  const labels = [];
  for (let t = s.getTime(); t < e.getTime(); t += step) labels.push(new Date(t).toISOString());
  return { start: s, end: e, unit, step, labels };
}

const keyOf = (date, unit) => {
  const t = date.getTime();
  const step = unit === 'hour' ? HOUR : DAY;
  return new Date(Math.floor(t / step) * step).toISOString();
};

function fillSeries(labels, rows, unit) {
  const m = new Map();
  for (const r of rows) m.set(keyOf(new Date(r.b), unit), Number(r.n));
  return labels.map((l) => m.get(l) ?? 0);
}

async function neonSeries(sql, r) {
  const { rows } = await query(sql, [r.start.toISOString(), r.end.toISOString()]);
  return fillSeries(r.labels, rows, r.unit);
}

// created_at rows out of Supabase, bucketed here (capped so a huge range cannot run away)
async function supabaseSeries(table, r) {
  const counts = new Map();
  let total = 0;
  for (let page = 0; page < 20; page++) {
    const { data, error } = await sb.from(table).select('created_at')
      .gte('created_at', r.start.toISOString()).lt('created_at', r.end.toISOString())
      .order('created_at', { ascending: true }).range(page * 1000, page * 1000 + 999);
    if (error) throw new Error(error.message);
    for (const row of data) {
      const k = keyOf(new Date(row.created_at), r.unit);
      counts.set(k, (counts.get(k) ?? 0) + 1);
      total++;
    }
    if (data.length < 1000) break;
  }
  return { series: r.labels.map((l) => counts.get(l) ?? 0), total };
}

const bucket = (r) => (r.unit === 'hour' ? "date_trunc('hour', {col} at time zone 'UTC')" : "date_trunc('day', {col} at time zone 'UTC')");
const b = (r, col) => bucket(r).replace('{col}', col);
const asUtc = (expr) => `to_char(${expr}, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')`;

export async function summary(opts) {
  const r = resolveRange(opts);
  const bk = (col) => asUtc(b(r, col));
  const win = (col) => `${col} >= $1 and ${col} < $2`;

  const [
    totalUsers, standingRows, newUsers, posts,
    logins, active, comments, messages,
  ] = await Promise.all([
    sb.from('profiles').select('id', { count: 'exact', head: true }),
    sb.from('user_standing').select('status, restricted_until, strikes'),
    supabaseSeries('profiles', r),
    supabaseSeries('posts', r),
    neonSeries(`select ${bk('created_at')} as b, count(*) as n from login_events where ${win('created_at')} group by 1`, r),
    neonSeries(`select ${bk('hour')} as b, count(distinct user_id) as n from active_hourly where ${win('hour')} group by 1`, r),
    neonSeries(`select ${bk('created_at')} as b, count(*) as n from comments where ${win('created_at')} group by 1`, r),
    neonSeries(`select ${bk('created_at')} as b, count(*) as n from messages where ${win('created_at')} group by 1`, r),
  ]);

  const params = [r.start.toISOString(), r.end.toISOString()];
  const [distinct, peakRow, hourOfDay, day24, day7, day30, open] = await Promise.all([
    query('select count(distinct user_id)::int as n from active_hourly where hour >= $1 and hour < $2', params),
    query('select hour, count(*)::int as n from active_hourly where hour >= $1 and hour < $2 group by hour order by n desc, hour desc limit 1', params),
    query(`select extract(hour from hour at time zone 'UTC')::int as h, count(*)::int as n from active_hourly where hour >= $1 and hour < $2 group by 1`, params),
    query("select count(distinct user_id)::int as n from active_hourly where hour > now() - interval '24 hours'"),
    query("select count(distinct user_id)::int as n from active_hourly where hour > now() - interval '7 days'"),
    query("select count(distinct user_id)::int as n from active_hourly where hour > now() - interval '30 days'"),
    query("select (select count(*)::int from reports where status = 'open') as reports, (select count(*)::int from appeals where status = 'pending') as appeals"),
  ]);

  // average daily active users over the range
  const dailyActive = await query(
    `select count(*)::int as n from (select date_trunc('day', hour at time zone 'UTC') d, user_id from active_hourly where hour >= $1 and hour < $2 group by 1, 2) x group by d`,
    params,
  );
  const days = Math.max(1, Math.round((r.end - r.start) / DAY));
  const sumDaily = dailyActive.rows.reduce((a, x) => a + x.n, 0);

  const now = Date.now();
  const st = standingRows.data ?? [];
  const restricted = st.filter((x) => x.status === 'restricted' && x.restricted_until && new Date(x.restricted_until) > now).length;
  const banned = st.filter((x) => x.status === 'banned').length;
  const struck = st.filter((x) => x.strikes > 0).length;

  const hours = Array(24).fill(0);
  for (const row of hourOfDay.rows) hours[row.h] = row.n;
  const hoursDivisor = Math.max(1, days);

  const sum = (a) => a.reduce((x, y) => x + y, 0);
  return {
    range: { from: r.start.toISOString(), to: r.end.toISOString(), unit: r.unit },
    kpis: {
      totalUsers: totalUsers.count ?? 0,
      newUsers: newUsers.total,
      activeUsers: distinct.rows[0].n,
      active24h: day24.rows[0].n,
      active7d: day7.rows[0].n,
      active30d: day30.rows[0].n,
      avgDailyActive: Math.round((sumDaily / days) * 10) / 10,
      logins: sum(logins),
      posts: posts.total,
      comments: sum(comments),
      messages: sum(messages),
      peak: peakRow.rows[0] ? { at: peakRow.rows[0].hour, users: peakRow.rows[0].n } : null,
      restricted, banned, struck,
      openReports: open.rows[0].reports,
      pendingAppeals: open.rows[0].appeals,
    },
    series: {
      labels: r.labels,
      activeUsers: active,
      logins,
      signups: newUsers.series,
      posts: posts.series,
      comments,
      messages,
    },
    hourOfDay: hours.map((n) => Math.round((n / hoursDivisor) * 10) / 10),
  };
}
