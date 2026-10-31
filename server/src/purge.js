import { tx } from './db.js';
import { admin } from './supabase.js';
import { HttpError } from './util.js';

const BUCKETS = ['avatars', 'covers', 'posts'];

/**
 * Removes a person completely: Neon rows, storage files, then the auth user
 * (profile, posts, reactions and friendships in Supabase cascade from it).
 * Used by "delete my account" and by the admin app.
 */
export async function purgeUser(id) {
  const { data: posts, error } = await admin.from('posts').select('id').eq('author_id', id);
  if (error) throw new HttpError(502, 'Could not read the posts.');
  const postIds = (posts ?? []).map((p) => p.id);

  await tx(async (db) => {
    if (postIds.length) {
      await db.query('delete from notifications where post_id = any($1::uuid[])', [postIds]);
      await db.query('delete from comments where post_id = any($1::uuid[])', [postIds]);
    }
    await db.query('delete from notifications where user_id = $1 or actor_id = $1', [id]);
    await db.query('delete from comments where user_id = $1', [id]); // replies cascade
    await db.query('delete from message_reactions where user_id = $1', [id]);
    await db.query('delete from comment_reactions where user_id = $1', [id]);
    await db.query('delete from conversations where user_a = $1 or user_b = $1', [id]); // messages cascade
    await db.query('delete from user_presence where user_id = $1', [id]);
    await db.query('delete from active_hourly where user_id = $1', [id]);
    await db.query('delete from login_events where user_id = $1', [id]);
  });

  for (const bucket of BUCKETS) {
    const { data: files } = await admin.storage.from(bucket).list(id, { limit: 1000 });
    if (files?.length) await admin.storage.from(bucket).remove(files.map((f) => `${id}/${f.name}`));
  }

  const { error: delErr } = await admin.auth.admin.deleteUser(id);
  if (delErr) throw new HttpError(502, 'Could not remove the account. Please try again.');
}
