import { Router } from 'express';
import { z } from 'zod';
import { query } from '../../db.js';
import { ah, HttpError, parse, uuid } from '../../util.js';
import { audit } from '../log.js';
import { can, requirePerm } from '../auth.js';
import { undo } from '../moderation.js';
import { shapeAction } from './users.js';

/**
 * Control: everything that was done to people, who did it, and a way to take
 * it back. Moderators can undo their own actions; admins and owners can undo anyone's.
 */
const r = Router();
const ctxOf = (req) => ({ adminId: req.admin.id, adminName: req.admin.name });

const canUndo = (admin, action) => can(admin, 'control.all') || (can(admin, 'control.own') && action.admin_id === admin.id);

r.get('/control/actions', requirePerm('control.own'), ah(async (req, res) => {
  const q = parse(z.object({
    admin: z.string().uuid().optional(),
    type: z.string().max(30).optional(),
    state: z.enum(['all', 'active', 'undone', 'undoable']).default('all'),
    q: z.string().max(80).optional(),
    page: z.coerce.number().int().min(1).max(10000).default(1),
  }), req.query);

  const where = [];
  const args = [];
  const add = (sql, v) => { args.push(v); where.push(sql.replaceAll('?', `$${args.length}`)); };

  // moderators only see their own work
  if (!can(req.admin, 'control.all')) add('admin_id = ?', req.admin.id);
  else if (q.admin) add('admin_id = ?', q.admin);
  if (q.type) add('type = ?', q.type);
  if (q.state === 'undone') where.push('reverted_at is not null');
  if (q.state === 'active') where.push('reverted_at is null');
  if (q.state === 'undoable') where.push('reverted_at is null and reversible');
  if (q.q?.trim()) add('(username ilike ? or reason ilike ?)', `%${q.q.trim().replace(/[%_]/g, ' ')}%`);

  const clause = where.length ? `where ${where.join(' and ')}` : '';
  const total = await query(`select count(*)::int as n from moderation_actions ${clause}`, args);
  const { rows } = await query(
    `select * from moderation_actions ${clause} order by created_at desc limit 30 offset ${(q.page - 1) * 30}`,
    args,
  );
  res.json({
    total: total.rows[0].n,
    actions: rows.map((a) => ({ ...shapeAction(a), canUndo: canUndo(req.admin, a) && !a.reverted_at && a.reversible })),
  });
}));

// who has been doing what: the picker and the "undo everything" screen
r.get('/control/admins', requirePerm('control.all'), ah(async (_req, res) => {
  const { rows } = await query(
    `select a.id, a.display_name, a.role, a.disabled,
            count(m.id) filter (where m.reverted_at is null)::int as active,
            count(m.id) filter (where m.reverted_at is null and m.reversible)::int as undoable,
            count(m.id) filter (where m.reverted_at is not null)::int as undone,
            max(m.created_at) as last_action
       from admins a left join moderation_actions m on m.admin_id = a.id
      group by a.id order by a.display_name`,
  );
  res.json({ admins: rows.map((x) => ({ id: x.id, name: x.display_name, role: x.role, disabled: x.disabled, active: x.active, undoable: x.undoable, undone: x.undone, lastAction: x.last_action })) });
}));

r.post('/control/actions/:id/undo', requirePerm('control.own'), ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const { reason } = parse(z.object({ reason: z.string().max(600) }), req.body);
  const { rows } = await query('select * from moderation_actions where id = $1', [id]);
  if (!rows[0]) throw new HttpError(404, 'Action not found.');
  if (!canUndo(req.admin, rows[0])) throw new HttpError(403, 'You can only undo your own actions.');

  const undone = await undo(ctxOf(req), id, reason);
  for (const u of undone) {
    await audit(req, 'control.undo', { targetType: 'user', targetId: u.userId, targetLabel: `@${u.username}`, details: { undid: u.type, actionId: u.id, reason } });
  }
  res.json({ undone });
}));

// roll back everything one admin did that can still be rolled back
r.post('/control/admins/:adminId/undo-all', requirePerm('control.all'), ah(async (req, res) => {
  const adminId = parse(uuid, req.params.adminId);
  const body = parse(z.object({
    reason: z.string().max(600),
    since: z.string().datetime({ offset: true }).optional(),
    types: z.array(z.string().max(30)).max(12).optional(),
  }), req.body);

  const args = [adminId];
  let extra = '';
  if (body.since) { args.push(body.since); extra += ` and created_at >= $${args.length}`; }
  if (body.types?.length) { args.push(body.types); extra += ` and type = any($${args.length}::text[])`; }
  const { rows } = await query(
    `select id from moderation_actions where admin_id = $1 and reverted_at is null and reversible ${extra} order by created_at desc`,
    args,
  );

  const done = [];
  const failed = [];
  for (const row of rows) {
    try {
      const fresh = await query('select reverted_at from moderation_actions where id = $1', [row.id]);
      if (fresh.rows[0]?.reverted_at) continue; // already undone as part of an earlier cascade
      const undone = await undo(ctxOf(req), row.id, body.reason);
      done.push(...undone);
    } catch (err) {
      failed.push({ id: row.id, error: err.message });
    }
  }
  await audit(req, 'control.undo_all', { targetType: 'admin', targetId: adminId, details: { undone: done.length, failed: failed.length, since: body.since ?? null, types: body.types ?? null, reason: body.reason } });
  res.json({ undone: done.length, failed });
}));

export default r;
