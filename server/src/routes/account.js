import { Router } from 'express';
import { tx } from '../db.js';
import { admin, getPost } from '../supabase.js';
import { ah, HttpError, parse, uuid } from '../util.js';
import { purgeUser } from '../purge.js';

const router = Router();

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
router.delete('/me', ah(async (req, res) => {
  await purgeUser(req.user.id);
  res.status(204).end();
}));

export default router;
