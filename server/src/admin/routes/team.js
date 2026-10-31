import { Router } from 'express';
import { z } from 'zod';
import { query } from '../../db.js';
import { pool } from '../../db.js';
import { admin as sb } from '../../supabase.js';
import { ah, HttpError, parse, uuid } from '../../util.js';
import { audit } from '../log.js';
import { generatePassword, hashPassword, requirePerm } from '../auth.js';
import { DEFAULTS, getSettings, saveSettings } from '../settings.js';

const r = Router();
const shape = (a) => ({
  id: a.id, email: a.email, name: a.display_name, role: a.role, disabled: a.disabled,
  lastLoginAt: a.last_login_at, createdAt: a.created_at, locked: Boolean(a.locked_until && new Date(a.locked_until) > new Date()),
  mustChangePassword: a.must_change_password,
});

// ---------------------------------------------------------------------------
// admin accounts (owner)
// ---------------------------------------------------------------------------
r.get('/team/admins', requirePerm('team'), ah(async (_req, res) => {
  const { rows } = await query('select * from admins order by created_at asc');
  const sessions = await query('select admin_id, count(*)::int as n, max(last_seen_at) as seen from admin_sessions where revoked_at is null and last_seen_at > now() - interval \'12 hours\' group by admin_id');
  const sm = new Map(sessions.rows.map((x) => [x.admin_id, x]));
  res.json({ admins: rows.map((a) => ({ ...shape(a), sessions: sm.get(a.id)?.n ?? 0, lastSeenAt: sm.get(a.id)?.seen ?? null })) });
}));

r.post('/team/admins', requirePerm('team'), ah(async (req, res) => {
  const v = parse(z.object({
    email: z.string().email().max(200).transform((e) => e.toLowerCase()),
    name: z.string().trim().min(1).max(60),
    role: z.enum(['owner', 'admin', 'moderator']),
  }), req.body);
  const temp = generatePassword();
  try {
    const { rows } = await query(
      `insert into admins (email, display_name, role, password_hash, must_change_password, created_by)
       values ($1,$2,$3,$4,true,$5) returning *`,
      [v.email, v.name, v.role, await hashPassword(temp), req.admin.id],
    );
    await audit(req, 'team.admin_create', { targetType: 'admin', targetId: rows[0].id, targetLabel: `${v.name} (${v.role})`, details: { email: v.email, role: v.role } });
    res.status(201).json({ admin: shape(rows[0]), temporaryPassword: temp });
  } catch (err) {
    if (err.code === '23505') throw new HttpError(409, 'An admin with that email already exists.');
    throw err;
  }
}));

r.patch('/team/admins/:id', requirePerm('team'), ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const v = parse(z.object({
    name: z.string().trim().min(1).max(60).optional(),
    role: z.enum(['owner', 'admin', 'moderator']).optional(),
    disabled: z.boolean().optional(),
  }), req.body);
  const { rows } = await query('select * from admins where id = $1', [id]);
  const a = rows[0];
  if (!a) throw new HttpError(404, 'Admin not found.');
  if (id === req.admin.id && (v.role !== undefined && v.role !== a.role || v.disabled)) throw new HttpError(400, 'You cannot change your own role or disable yourself.');
  if (a.role === 'owner' && (v.role && v.role !== 'owner' || v.disabled)) {
    const owners = await query("select count(*)::int as n from admins where role = 'owner' and not disabled");
    if (owners.rows[0].n <= 1) throw new HttpError(400, 'There must always be one active owner.');
  }
  const up = await query(
    'update admins set display_name = coalesce($2, display_name), role = coalesce($3, role), disabled = coalesce($4, disabled) where id = $1 returning *',
    [id, v.name ?? null, v.role ?? null, v.disabled ?? null],
  );
  if (v.disabled || (v.role && v.role !== a.role)) await query('update admin_sessions set revoked_at = now() where admin_id = $1 and revoked_at is null', [id]);
  await audit(req, 'team.admin_update', { targetType: 'admin', targetId: id, targetLabel: a.display_name, details: { before: { role: a.role, disabled: a.disabled, name: a.display_name }, after: v } });
  res.json({ admin: shape(up.rows[0]) });
}));

r.post('/team/admins/:id/reset-password', requirePerm('team'), ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const temp = generatePassword();
  const { rows } = await query('update admins set password_hash = $2, must_change_password = true, failed_attempts = 0, locked_until = null where id = $1 returning display_name', [id, await hashPassword(temp)]);
  if (!rows[0]) throw new HttpError(404, 'Admin not found.');
  await query('update admin_sessions set revoked_at = now() where admin_id = $1 and revoked_at is null', [id]);
  await audit(req, 'team.admin_reset_password', { targetType: 'admin', targetId: id, targetLabel: rows[0].display_name });
  res.json({ temporaryPassword: temp });
}));

r.post('/team/admins/:id/sign-out', requirePerm('team'), ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const { rowCount } = await query('update admin_sessions set revoked_at = now() where admin_id = $1 and revoked_at is null', [id]);
  await audit(req, 'team.admin_sign_out', { targetType: 'admin', targetId: id, details: { sessions: rowCount } });
  res.json({ ended: rowCount });
}));

// ---------------------------------------------------------------------------
// settings (owner)
// ---------------------------------------------------------------------------
const templateList = z.array(z.object({ label: z.string().trim().min(1).max(40), text: z.string().trim().min(8).max(500) })).max(12);
const settingsSchema = z.object({
  restrictBaseHours: z.number().int().min(1).max(168),
  restrictMaxHours: z.number().int().min(1).max(8760),
  strikeAutoRestrictAt: z.number().int().min(0).max(20),
  strikeAutoBanAt: z.number().int().min(0).max(50),
  notifyRestricted: z.boolean(),
  sessionIdleMinutes: z.number().int().min(5).max(480),
  templates: z.record(z.string().max(30), templateList).optional(),
}).partial();

r.get('/settings', requirePerm('team'), ah(async (_req, res) => {
  res.json({ settings: await getSettings({ fresh: true }), defaults: DEFAULTS });
}));

r.put('/settings', requirePerm('team'), ah(async (req, res) => {
  const v = parse(settingsSchema, req.body);
  const before = await getSettings({ fresh: true });
  const next = { ...before, ...v };
  if (next.restrictMaxHours < next.restrictBaseHours) throw new HttpError(400, 'The longest restriction cannot be shorter than the first one.');
  if (next.strikeAutoBanAt && next.strikeAutoRestrictAt && next.strikeAutoBanAt <= next.strikeAutoRestrictAt) throw new HttpError(400, 'Automatic ban must come after automatic restriction.');
  const saved = await saveSettings(v, req.admin.id);
  const changed = Object.keys(v).filter((k) => JSON.stringify(v[k]) !== JSON.stringify(before[k]));
  await audit(req, 'settings.update', { details: { changed, before: Object.fromEntries(changed.filter((k) => k !== 'templates').map((k) => [k, before[k]])), after: Object.fromEntries(changed.filter((k) => k !== 'templates').map((k) => [k, v[k]])) } });
  res.json({ settings: saved });
}));

// ---------------------------------------------------------------------------
// system health
// ---------------------------------------------------------------------------
r.get('/system', requirePerm('system'), ah(async (_req, res) => {
  const t0 = Date.now();
  let dbMs = null; let dbOk = false;
  try { await query('select 1'); dbMs = Date.now() - t0; dbOk = true; } catch { /* reported below */ }
  const t1 = Date.now();
  let sbMs = null; let sbOk = false;
  try { const { error } = await sb.from('profiles').select('id', { head: true, count: 'exact' }).limit(1); sbOk = !error; sbMs = Date.now() - t1; } catch { /* reported below */ }

  const counts = dbOk
    ? (await query(`select (select count(*)::int from admins) as admins,
                           (select count(*)::int from admin_logs) as logs,
                           (select count(*)::int from moderation_actions) as actions,
                           (select count(*)::int from admin_sessions where revoked_at is null and last_seen_at > now() - interval '30 minutes') as sessions,
                           (select max(created_at) from admin_logs) as last_log`)).rows[0]
    : {};
  res.json({
    server: { uptimeSeconds: Math.round(process.uptime()), node: process.version, memoryMb: Math.round(process.memoryUsage().rss / 1048576), poolTotal: pool.totalCount, poolIdle: pool.idleCount, poolWaiting: pool.waitingCount },
    neon: { ok: dbOk, ms: dbMs },
    supabase: { ok: sbOk, ms: sbMs },
    counts,
  });
}));

export default r;
