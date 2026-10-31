import { Router } from 'express';
import { z } from 'zod';
import { query } from '../../db.js';
import { admin as sb, loadProfiles } from '../../supabase.js';
import { ah, HttpError, parse, uuid } from '../../util.js';
import { audit } from '../log.js';
import { requirePerm } from '../auth.js';
import { perform, reasonOk, standingOf } from '../moderation.js';

const r = Router();
const ctxOf = (req) => ({ adminId: req.admin.id, adminName: req.admin.name });

// ---------------------------------------------------------------------------
// reports from people
// ---------------------------------------------------------------------------
r.get('/reports', requirePerm('reports'), ah(async (req, res) => {
  const q = parse(z.object({ status: z.enum(['open', 'actioned', 'dismissed', 'all']).default('open'), page: z.coerce.number().int().min(1).default(1) }), req.query);
  const args = [];
  let clause = '';
  if (q.status !== 'all') { args.push(q.status); clause = 'where status = $1'; }
  const total = await query(`select count(*)::int as n from reports ${clause}`, args);
  const { rows } = await query(`select * from reports ${clause} order by created_at desc limit 25 offset ${(q.page - 1) * 25}`, args);

  const users = await loadProfiles(rows.flatMap((x) => [x.reporter_id, x.target_user_id]));
  const postIds = rows.filter((x) => x.target_type === 'post').map((x) => x.target_id);
  const commentIds = rows.filter((x) => x.target_type === 'comment').map((x) => x.target_id);
  const [posts, comments] = await Promise.all([
    postIds.length ? sb.from('posts').select('id, body, image_path').in('id', postIds) : { data: [] },
    commentIds.length ? query('select id, body from comments where id = any($1::uuid[])', [commentIds]) : { rows: [] },
  ]);
  const pb = new Map((posts.data ?? []).map((p) => [p.id, p.body]));
  const cb = new Map(comments.rows.map((c) => [c.id, c.body]));

  res.json({
    total: total.rows[0].n,
    reports: rows.map((x) => ({
      id: x.id, targetType: x.target_type, targetId: x.target_id, reason: x.reason, details: x.details,
      status: x.status, createdAt: x.created_at, handledName: x.handled_name, resolutionNote: x.resolution_note, handledAt: x.handled_at,
      reporter: users.get(x.reporter_id),
      targetUser: x.target_user_id ? users.get(x.target_user_id) : null,
      preview: x.target_type === 'post' ? (pb.get(x.target_id) ?? null) : x.target_type === 'comment' ? (cb.get(x.target_id) ?? null) : null,
      gone: x.target_type !== 'user' && !(x.target_type === 'post' ? pb.has(x.target_id) : cb.has(x.target_id)),
    })),
  });
}));

r.post('/reports/:id/resolve', requirePerm('reports'), ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const body = parse(z.object({ resolution: z.enum(['actioned', 'dismissed']), note: z.string().trim().max(300).optional() }), req.body);
  const { rows } = await query(
    `update reports set status = $2, handled_by = $3, handled_name = $4, resolution_note = $5, handled_at = now()
      where id = $1 and status = 'open' returning *`,
    [id, body.resolution, req.admin.id, req.admin.name, body.note ?? null],
  );
  if (!rows[0]) throw new HttpError(404, 'That report is already handled.');
  await audit(req, `report.${body.resolution}`, { targetType: 'report', targetId: id, targetLabel: `${rows[0].target_type} report`, details: { note: body.note ?? null, targetUser: rows[0].target_user_id } });
  res.json({ ok: true });
}));

// ---------------------------------------------------------------------------
// appeals from banned or restricted people
// ---------------------------------------------------------------------------
r.get('/appeals', requirePerm('appeals'), ah(async (req, res) => {
  const q = parse(z.object({ status: z.enum(['pending', 'approved', 'denied', 'all']).default('pending') }), req.query);
  const args = [];
  let clause = '';
  if (q.status !== 'all') { args.push(q.status); clause = 'where status = $1'; }
  const { rows } = await query(`select * from appeals ${clause} order by created_at desc limit 100`, args);
  const users = await loadProfiles(rows.map((x) => x.user_id));
  const standing = await Promise.all(rows.map(async (x) => (await standingOf(x.user_id).catch(() => null))?.now ?? null));
  const why = await query("select distinct on (user_id) user_id, type, reason from moderation_actions where user_id = any($1::uuid[]) and type in ('ban', 'restrict') and reverted_at is null order by user_id, created_at desc", [rows.map((x) => x.user_id)]);
  const wm = new Map(why.rows.map((x) => [x.user_id, x]));
  res.json({
    appeals: rows.map((x, i) => ({
      id: x.id, userId: x.user_id, user: users.get(x.user_id), message: x.message, status: x.status, createdAt: x.created_at,
      decidedName: x.decided_name, decisionReason: x.decision_reason, decidedAt: x.decided_at,
      standing: standing[i] ? { status: standing[i].status, until: standing[i].until } : null,
      original: wm.get(x.user_id) ? { type: wm.get(x.user_id).type, reason: wm.get(x.user_id).reason } : null,
    })),
  });
}));

r.post('/appeals/:id/decide', requirePerm('appeals'), ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const body = parse(z.object({ decision: z.enum(['approve', 'deny']), reason: z.string().max(600) }), req.body);
  const reason = reasonOk(body.reason);
  const { rows } = await query("select * from appeals where id = $1 and status = 'pending'", [id]);
  const a = rows[0];
  if (!a) throw new HttpError(404, 'That appeal was already decided.');

  let applied = null;
  if (body.decision === 'approve') {
    const { now } = await standingOf(a.user_id);
    if (now.status === 'banned') applied = (await perform(ctxOf(req), a.user_id, 'unban', { reason })).actions[0];
    else if (now.status === 'restricted') applied = (await perform(ctxOf(req), a.user_id, 'unrestrict', { reason })).actions[0];
  }
  await query(
    `update appeals set status = $2, decided_by = $3, decided_name = $4, decision_reason = $5, decided_at = now() where id = $1`,
    [id, body.decision === 'approve' ? 'approved' : 'denied', req.admin.id, req.admin.name, reason],
  );
  await audit(req, `appeal.${body.decision}`, { targetType: 'user', targetId: a.user_id, targetLabel: `@${a.username}`, details: { appealId: id, reason, actionId: applied?.id ?? null } });
  res.json({ ok: true });
}));

export default r;
