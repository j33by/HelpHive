import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { getPost, loadProfiles } from '../supabase.js';
import { notify } from '../notify.js';
import { ah, HttpError, parse, reactionKind, text, uuid } from '../util.js';

const router = Router();

const shapeComment = (row, users) => ({
  id: row.id,
  postId: row.post_id,
  parentId: row.parent_id,
  user: users.get(row.user_id),
  body: row.body,
  edited: row.edited,
  createdAt: row.created_at,
  reactionCount: row.reaction_count ?? 0,
  myReaction: row.my_reaction ?? null,
});

const SELECT = `
  select c.id, c.post_id, c.parent_id, c.user_id, c.body, c.edited, c.created_at,
         (select count(*)::int from comment_reactions r where r.comment_id = c.id) as reaction_count,
         (select r.kind from comment_reactions r where r.comment_id = c.id and r.user_id = $2) as my_reaction
  from comments c`;

async function loadOne(id, me) {
  const { rows } = await query(`${SELECT} where c.id = $1`, [id, me]);
  if (!rows[0]) return null;
  const users = await loadProfiles([rows[0].user_id]);
  return shapeComment(rows[0], users);
}

// All comments on a post, oldest first. The app nests replies under their parent.
router.get('/posts/:postId/comments', ah(async (req, res) => {
  const postId = parse(uuid, req.params.postId);
  const { rows } = await query(`${SELECT} where c.post_id = $1 order by c.created_at asc limit 500`, [postId, req.user.id]);
  const users = await loadProfiles(rows.map((r) => r.user_id));
  res.json({ comments: rows.map((r) => shapeComment(r, users)) });
}));

// Comment totals for a page of feed posts.
router.post('/comments/counts', ah(async (req, res) => {
  const { postIds } = parse(z.object({ postIds: z.array(uuid).max(50) }), req.body);
  if (!postIds.length) return res.json({ counts: {} });
  const { rows } = await query(
    'select post_id, count(*)::int as n from comments where post_id = any($1::uuid[]) group by post_id',
    [postIds],
  );
  res.json({ counts: Object.fromEntries(rows.map((r) => [r.post_id, r.n])) });
}));

router.post('/posts/:postId/comments', ah(async (req, res) => {
  const me = req.user.id;
  const postId = parse(uuid, req.params.postId);
  const { body, parentId } = parse(
    z.object({ body: text(1000), parentId: uuid.nullish() }),
    req.body,
  );

  const post = await getPost(postId);
  if (!post) throw new HttpError(404, 'That post is gone.');

  // Replies are one level deep: answering a reply attaches to the same thread.
  let rootId = null;
  let replyTargetUser = null;
  if (parentId) {
    const { rows } = await query('select id, parent_id, user_id, post_id from comments where id = $1', [parentId]);
    const parent = rows[0];
    if (!parent || parent.post_id !== postId) throw new HttpError(404, 'That comment is gone.');
    rootId = parent.parent_id ?? parent.id;
    replyTargetUser = parent.user_id;
  }

  const { rows } = await query(
    'insert into comments (post_id, parent_id, user_id, body) values ($1, $2, $3, $4) returning id',
    [postId, rootId, me, body],
  );
  const id = rows[0].id;

  if (replyTargetUser) {
    await notify({ userId: replyTargetUser, actorId: me, type: 'comment_reply', postId, commentId: id, snippet: body });
  }
  if (post.author_id !== replyTargetUser) {
    await notify({ userId: post.author_id, actorId: me, type: 'post_comment', postId, commentId: id, snippet: body });
  }

  res.status(201).json({ comment: await loadOne(id, me) });
}));

router.put('/comments/:id', ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const { body } = parse(z.object({ body: text(1000) }), req.body);
  const { rowCount } = await query(
    'update comments set body = $1, edited = true, updated_at = now() where id = $2 and user_id = $3',
    [body, id, req.user.id],
  );
  if (!rowCount) throw new HttpError(404, 'Comment not found.');
  res.json({ comment: await loadOne(id, req.user.id) });
}));

// The author can delete their comment; so can the owner of the post it sits under.
router.delete('/comments/:id', ah(async (req, res) => {
  const me = req.user.id;
  const id = parse(uuid, req.params.id);
  const { rows } = await query('select user_id, post_id from comments where id = $1', [id]);
  const comment = rows[0];
  if (!comment) return res.status(204).end();

  if (comment.user_id !== me) {
    const post = await getPost(comment.post_id);
    if (!post || post.author_id !== me) throw new HttpError(403, 'You can only delete your own comments.');
  }

  await query(
    'delete from notifications where comment_id in (select id from comments where id = $1 or parent_id = $1)',
    [id],
  );
  await query('delete from comments where id = $1', [id]); // replies and reactions cascade
  res.status(204).end();
}));

router.put('/comments/:id/reaction', ah(async (req, res) => {
  const me = req.user.id;
  const id = parse(uuid, req.params.id);
  const { kind } = parse(z.object({ kind: reactionKind.nullable() }), req.body);

  const { rows } = await query('select user_id, post_id from comments where id = $1', [id]);
  const comment = rows[0];
  if (!comment) throw new HttpError(404, 'Comment not found.');

  if (kind) {
    await query(
      `insert into comment_reactions (comment_id, user_id, kind) values ($1, $2, $3)
       on conflict (comment_id, user_id) do update set kind = excluded.kind`,
      [id, me, kind],
    );
    await notify({ userId: comment.user_id, actorId: me, type: 'comment_reaction', postId: comment.post_id, commentId: id, snippet: kind });
  } else {
    await query('delete from comment_reactions where comment_id = $1 and user_id = $2', [id, me]);
    await query(
      `delete from notifications where user_id = $1 and actor_id = $2 and type = 'comment_reaction' and comment_id = $3`,
      [comment.user_id, me, id],
    );
  }

  const fresh = await loadOne(id, me);
  res.json({ reactionCount: fresh.reactionCount, myReaction: fresh.myReaction });
}));

export default router;
