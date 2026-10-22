import { createClient } from '@supabase/supabase-js';
import { config } from './config.js';
import { HttpError } from './util.js';

// Service-role client. It never leaves this process; clients only ever hold the anon key.
export const admin = createClient(config.supabaseUrl, config.supabaseServiceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const TTL_MS = 60_000;
const cache = new Map();

const shape = (p) => ({
  id: p.id,
  username: p.username,
  fullName: p.full_name || '',
  avatarUrl: p.avatar_url || null,
});

const ghost = (id) => ({ id, username: 'deleted', fullName: 'Deleted user', avatarUrl: null });

/** id -> { id, username, fullName, avatarUrl } for every id given. */
export async function loadProfiles(ids) {
  const wanted = [...new Set(ids.filter(Boolean))];
  const found = new Map();
  const missing = [];
  const now = Date.now();

  for (const id of wanted) {
    const hit = cache.get(id);
    if (hit && hit.exp > now) found.set(id, hit.value);
    else missing.push(id);
  }

  if (missing.length) {
    const { data, error } = await admin
      .from('profiles')
      .select('id, username, full_name, avatar_url')
      .in('id', missing);
    if (error) throw new HttpError(502, 'Could not reach the profile service.');

    if (cache.size > 5000) cache.clear();
    for (const row of data ?? []) {
      const value = shape(row);
      cache.set(row.id, { value, exp: now + TTL_MS });
      found.set(row.id, value);
    }
    for (const id of missing) if (!found.has(id)) found.set(id, ghost(id));
  }
  return found;
}

export async function profileExists(id) {
  const { data, error } = await admin.from('profiles').select('id').eq('id', id).maybeSingle();
  if (error) throw new HttpError(502, 'Could not reach the profile service.');
  return Boolean(data);
}

export async function getPost(id) {
  const { data, error } = await admin
    .from('posts')
    .select('id, author_id, image_path')
    .eq('id', id)
    .maybeSingle();
  if (error) throw new HttpError(502, 'Could not reach the post service.');
  return data;
}

/** id -> post summary for a handful of posts (used by the resolved-comments list). */
export async function getPosts(ids) {
  const wanted = [...new Set(ids.filter(Boolean))];
  if (!wanted.length) return new Map();
  const { data, error } = await admin
    .from('posts')
    .select('id, author_id, body, category, is_resolved, created_at, image_path')
    .in('id', wanted);
  if (error) throw new HttpError(502, 'Could not reach the post service.');
  return new Map((data ?? []).map((p) => [p.id, p]));
}

/** Marks a post resolved (never un-resolves it; the owner does that by hand). */
export async function markResolved(postId) {
  const { error } = await admin.from('posts').update({ is_resolved: true }).eq('id', postId);
  if (error) console.error('could not mark post resolved:', error.message);
  return !error;
}
