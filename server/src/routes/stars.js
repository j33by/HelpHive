import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { getPosts, loadProfiles } from '../supabase.js';
import { badgeKey, loadStars, withStars } from '../stars.js';
import { ah, cursor, parse, uuid } from '../util.js';

const router = Router();
const PAGE = 20;

// One person's star total and badge.
router.get('/users/:id/stars', ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const stars = (await loadStars([id])).get(id) ?? 0;
  res.json({ stars, badge: badgeKey(stars) });
}));

// Star totals for a page of feed authors, so post cards can show their badge.
router.post('/users/stars', ah(async (req, res) => {
  const { userIds } = parse(z.object({ userIds: z.array(uuid).max(60) }), req.body);
  const stars = await loadStars(userIds);
  res.json({ stars: Object.fromEntries(stars) });
}));

// The comments this person got starred, newest star first, each with the post it answered.
router.get('/users/:id/resolved', ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const { before } = parse(z.object({ before: cursor }), req.query);

  const { rows } = await query(
    `select id, post_id, body, created_at, helpful_at
       from comments
      where user_id = $1 and is_helpful
        and ($2::timestamptz is null or helpful_at < $2::timestamptz)
      order by helpful_at desc
      limit $3`,
    [id, before ?? null, PAGE + 1],
  );
  const page = rows.slice(0, PAGE);
  const posts = await getPosts(page.map((r) => r.post_id));
  const users = await withStars(await loadProfiles([...posts.values()].map((p) => p.author_id)));

  res.json({
    hasMore: rows.length > PAGE,
    items: page
      .filter((r) => posts.has(r.post_id))
      .map((r) => {
        const p = posts.get(r.post_id);
        return {
          comment: { id: r.id, body: r.body, createdAt: r.created_at, helpfulAt: r.helpful_at },
          post: {
            id: p.id,
            body: p.body,
            category: p.category,
            isResolved: p.is_resolved,
            hasImage: Boolean(p.image_path),
            createdAt: p.created_at,
            author: users.get(p.author_id),
          },
        };
      }),
  });
}));

export default router;
