import { admin } from './supabase.js';

/**
 * Account standing: active, restricted or banned. The truth lives in Supabase
 * (public.user_standing) so row level security can enforce it on direct writes.
 * This file is the Node side of the same rule: it reads the row, works out the
 * effective status (a restriction ends by itself when its time is up) and
 * stops requests that the person is not allowed to make.
 */
const TTL_MS = 15_000;
const cache = new Map();

export function effective(row) {
  if (!row) return { status: 'active', until: null, reason: null, strikes: 0, bannedAt: null };
  let status = row.status;
  if (status === 'restricted' && !(row.restricted_until && new Date(row.restricted_until) > new Date())) status = 'active';
  return {
    status,
    until: status === 'restricted' ? new Date(row.restricted_until).toISOString() : null,
    reason: status === 'active' ? null : row.reason ?? null,
    strikes: row.strikes ?? 0,
    bannedAt: row.banned_at ?? null,
  };
}

export async function getStanding(userId, { fresh = false } = {}) {
  const hit = cache.get(userId);
  if (!fresh && hit && hit.exp > Date.now()) return hit.value;
  const { data, error } = await admin.from('user_standing').select('*').eq('user_id', userId).maybeSingle();
  if (error) throw new Error(`standing lookup failed: ${error.message}`);
  const value = effective(data);
  if (cache.size > 5000) cache.clear();
  cache.set(userId, { value, exp: Date.now() + TTL_MS });
  return value;
}

export const forgetStanding = (userId) => cache.delete(userId);

// What a banned person may still call: see why, appeal, or delete their own account.
const BANNED_OK = [
  ['GET', /^\/me\/standing$/],
  ['POST', /^\/me\/appeal$/],
  ['DELETE', /^\/me$/],
];
// What a restricted person may still change: tidy their own alerts, mark chats read, leave.
const RESTRICTED_OK = [
  ['POST', /^\/notifications\/read$/],
  ['POST', /^\/notifications\/[0-9a-f-]{36}\/read$/],
  ['DELETE', /^\/notifications(\/[0-9a-f-]{36})?$/],
  ['POST', /^\/conversations\/[0-9a-f-]{36}\/read$/],
  ['POST', /^\/me\/appeal$/],
  ['DELETE', /^\/me$/],
];
const allowed = (list, req) => list.some(([m, re]) => m === req.method && re.test(req.path));

export async function enforceStanding(req, res, next) {
  let s;
  try {
    s = await getStanding(req.user.id);
  } catch (err) {
    // If the moderation table is missing or Supabase hiccups, do not lock everyone out.
    console.error('standing check skipped:', err.message);
    req.standing = effective(null);
    return next();
  }
  req.standing = s;
  if (s.status === 'banned' && !allowed(BANNED_OK, req)) {
    return res.status(403).json({ error: 'This account has been banned.', code: 'banned' });
  }
  if (s.status === 'restricted' && req.method !== 'GET' && !allowed(RESTRICTED_OK, req)) {
    return res.status(403).json({ error: 'Your account is restricted right now.', code: 'restricted', until: s.until });
  }
  next();
}
