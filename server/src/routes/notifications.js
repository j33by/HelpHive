import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { loadProfiles } from '../supabase.js';
import { ah, cursor, parse, uuid } from '../util.js';

const router = Router();

const PAGE = 30;

router.get('/notifications', ah(async (req, res) => {
  const { before } = parse(z.object({ before: cursor }), req.query);
  const { rows } = await query(
    `select id, actor_id, type, post_id, comment_id, snippet, read_at, created_at
       from notifications
      where user_id = $1 and ($2::timestamptz is null or created_at < $2::timestamptz)
      order by created_at desc
      limit $3`,
    [req.user.id, before ?? null, PAGE + 1],
  );
  const page = rows.slice(0, PAGE);
  const users = await loadProfiles(page.map((r) => r.actor_id));
  res.json({
    hasMore: rows.length > PAGE,
    notifications: page.map((r) => ({
      id: r.id,
      type: r.type,
      actor: users.get(r.actor_id),
      postId: r.post_id,
      commentId: r.comment_id,
      snippet: r.snippet,
      read: r.read_at !== null,
      createdAt: r.created_at,
    })),
  });
}));

// One cheap call the app polls for its two tab badges.
router.get('/badges', ah(async (req, res) => {
  const me = req.user.id;
  const [n, m] = await Promise.all([
    query('select count(*)::int as n from notifications where user_id = $1 and read_at is null', [me]),
    query(
      `select count(*)::int as n
         from conversations c
         join messages m on m.conversation_id = c.id
        where (c.user_a = $1 or c.user_b = $1)
          and m.sender_id <> $1 and m.deleted_at is null
          and m.created_at > case when c.user_a = $1 then c.a_read_at else c.b_read_at end`,
      [me],
    ),
  ]);
  res.json({ notifications: n.rows[0].n, messages: m.rows[0].n });
}));

router.post('/notifications/read', ah(async (req, res) => {
  await query('update notifications set read_at = now() where user_id = $1 and read_at is null', [req.user.id]);
  res.status(204).end();
}));

router.post('/notifications/:id/read', ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  await query('update notifications set read_at = now() where id = $1 and user_id = $2 and read_at is null', [id, req.user.id]);
  res.status(204).end();
}));

// Clear every notification of the signed-in user.
router.delete('/notifications', ah(async (req, res) => {
  await query('delete from notifications where user_id = $1', [req.user.id]);
  res.status(204).end();
}));

router.delete('/notifications/:id', ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  await query('delete from notifications where id = $1 and user_id = $2', [id, req.user.id]);
  res.status(204).end();
}));

export default router;
