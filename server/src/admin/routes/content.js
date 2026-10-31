import { Router } from 'express';
import { z } from 'zod';
import { query } from '../../db.js';
import { admin as sb } from '../../supabase.js';
import { loadProfiles } from '../../supabase.js';
import { ah, HttpError, parse } from '../../util.js';
import { requirePerm } from '../auth.js';
import { publicUrl, safeTerm } from '../directory.js';

const r = Router();

// every post on the platform, newest first
r.get('/content/posts', requirePerm('content.view'), ah(async (req, res) => {
  const q = parse(z.object({
    q: z.string().max(80).optional(),
    category: z.enum(['general', 'request', 'offer']).optional(),
    page: z.coerce.number().int().min(1).max(10000).default(1),
  }), req.query);
  const from = (q.page - 1) * 20;
  let s = sb.from('posts').select('*', { count: 'exact' });
  const term = safeTerm(q.q);
  if (term) s = s.ilike('body', `%${term}%`);
  if (q.category) s = s.eq('category', q.category);
  const { data, count, error } = await s.order('created_at', { ascending: false }).range(from, from + 19);
  if (error) throw new HttpError(502, 'Could not read the posts.');

  const users = await loadProfiles(data.map((p) => p.author_id));
  const ids = data.map((p) => p.id);
  const { rows } = ids.length ? await query('select post_id, count(*)::int as n from comments where post_id = any($1::uuid[]) group by post_id', [ids]) : { rows: [] };
  const cc = new Map(rows.map((x) => [x.post_id, x.n]));
  res.json({
    total: count ?? 0,
    posts: data.map((p) => ({
      id: p.id, body: p.body, category: p.category, resolved: p.is_resolved, imageUrl: publicUrl(p.image_path),
      createdAt: p.created_at, comments: cc.get(p.id) ?? 0, author: users.get(p.author_id),
    })),
  });
}));

r.get('/content/posts/:id/comments', requirePerm('content.view'), ah(async (req, res) => {
  const { rows } = await query('select id, parent_id, user_id, body, created_at, is_helpful from comments where post_id = $1 order by created_at asc limit 500', [req.params.id]);
  const users = await loadProfiles(rows.map((c) => c.user_id));
  res.json({ comments: rows.map((c) => ({ id: c.id, parentId: c.parent_id, body: c.body, helpful: c.is_helpful, createdAt: c.created_at, author: users.get(c.user_id) })) });
}));

r.get('/content/comments', requirePerm('content.view'), ah(async (req, res) => {
  const q = parse(z.object({ q: z.string().max(80).optional(), page: z.coerce.number().int().min(1).max(10000).default(1) }), req.query);
  const term = safeTerm(q.q);
  const where = term ? 'where body ilike $1' : 'where $1::text is null';
  const { rows } = await query(`select id, post_id, parent_id, user_id, body, created_at from comments ${where} order by created_at desc limit 20 offset $2`, [term ? `%${term}%` : null, (q.page - 1) * 20]);
  const total = await query(`select count(*)::int as n from comments ${where}`, [term ? `%${term}%` : null]);
  const users = await loadProfiles(rows.map((c) => c.user_id));
  res.json({ total: total.rows[0].n, comments: rows.map((c) => ({ id: c.id, postId: c.post_id, isReply: Boolean(c.parent_id), body: c.body, createdAt: c.created_at, author: users.get(c.user_id) })) });
}));

export default r;
