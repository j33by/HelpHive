import { admin as sb } from '../supabase.js';
import { HttpError } from '../util.js';

/**
 * Emails and sign-in times live in Supabase Auth, which cannot be searched by
 * email. This keeps a short-lived id -> auth info map (one listing per minute at most).
 */
let cache = { at: 0, map: new Map(), pending: null };

export async function authIndex(force = false) {
  if (!force && Date.now() - cache.at < 60_000) return cache.map;
  if (cache.pending) return cache.pending;
  cache.pending = (async () => {
    const map = new Map();
    for (let page = 1; page <= 20; page++) {
      const { data, error } = await sb.auth.admin.listUsers({ page, perPage: 1000 });
      if (error) throw new HttpError(502, 'Could not read the account list from Supabase Auth.');
      for (const u of data.users) {
        map.set(u.id, {
          email: u.email ?? '',
          lastSignInAt: u.last_sign_in_at ?? null,
          createdAt: u.created_at,
          confirmed: Boolean(u.email_confirmed_at),
          provider: u.app_metadata?.provider ?? 'email',
        });
      }
      if (data.users.length < 1000) break;
    }
    cache = { at: Date.now(), map, pending: null };
    return map;
  })().finally(() => { cache.pending = null; });
  return cache.pending;
}

export const dropAuthIndex = () => { cache.at = 0; };

/** Removes characters that would break a PostgREST filter string. */
export const safeTerm = (q) => String(q ?? '').replace(/[%,()*\\"']/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 60);

export const publicUrl = (path) => (path ? sb.storage.from('posts').getPublicUrl(path).data.publicUrl : null);
