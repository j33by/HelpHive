import { Router } from 'express';
import { query, tx } from '../db.js';
import { admin, getPost } from '../supabase.js';
import { ah, HttpError, parse, uuid } from '../util.js';

const router = Router();

const BUCKETS = ['avatars', 'covers', 'posts'];

// Deleting a post removes the row (Supabase), its image (storage) and everything
// hanging off it in Neon. Only the author may do it.
router.delete('/posts/:id', ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const post = await getPost(id);

  if (post) {
    if (post.author_id !== req.user.id) throw new HttpError(403, 'You can only delete your own posts.');
    if (post.image_path) await admin.storage.from('posts').remove([post.image_path]);
    const { error } = await admin.from('posts').delete().eq('id', id);
    if (error) throw new HttpError(502, 'Could not delete the post.');
  }

  await tx(async (db) => {
    await db.query('delete from notifications where post_id = $1', [id]);
    await db.query('delete from comments where post_id = $1', [id]);
  });
  res.status(204).end();
}));

// Full account removal: Neon rows, storage files, then the auth user itself.
// The profile, posts, reactions and friendships in Supabase cascade from the auth user.
router.delete('/me', ah(async (req, res) => {
  const me = req.user.id;

  const { data: posts, error } = await admin.from('posts').select('id').eq('author_id', me);
  if (error) throw new HttpError(502, 'Could not read your posts.');
  const postIds = (posts ?? []).map((p) => p.id);

  await tx(async (db) => {
    if (postIds.length) {
      await db.query('delete from notifications where post_id = any($1::uuid[])', [postIds]);
      await db.query('delete from comments where post_id = any($1::uuid[])', [postIds]);
    }
    await db.query('delete from notifications where user_id = $1 or actor_id = $1', [me]);
    await db.query('delete from comments where user_id = $1', [me]); // replies cascade
    await db.query('delete from message_reactions where user_id = $1', [me]);
    await db.query('delete from comment_reactions where user_id = $1', [me]);
    await db.query('delete from conversations where user_a = $1 or user_b = $1', [me]); // messages cascade
  });

  for (const bucket of BUCKETS) {
    const { data: files } = await admin.storage.from(bucket).list(me, { limit: 1000 });
    if (files?.length) {
      await admin.storage.from(bucket).remove(files.map((f) => `${me}/${f.name}`));
    }
  }

  const { error: delErr } = await admin.auth.admin.deleteUser(me);
  if (delErr) throw new HttpError(502, 'Could not remove your account. Please try again.');
  res.status(204).end();
}));

export default router;
