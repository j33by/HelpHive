import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { query } from '../../db.js';
import { ah, HttpError, parse } from '../../util.js';
import { audit } from '../log.js';
import { config } from '../../config.js';
import {
  dummyVerify, hashPassword, publicAdmin, requireAdmin, signToken, verifyPassword,
} from '../auth.js';
import { ENVELOPES, getSettings } from '../settings.js';

/** Sign-in is public; everything else here needs a session. */
export const publicRoutes = Router();
export const sessionRoutes = Router();

const loginLimiter = rateLimit({
  windowMs: 10 * 60_000,
  limit: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many sign-in attempts from this network. Wait a few minutes.' },
});

const MAX_FAILS = 5;
const LOCK_MIN = 15;

publicRoutes.get('/ping', (_req, res) => res.json({ ok: true, admin: Boolean(config.adminJwtSecret) }));

publicRoutes.post('/auth/login', loginLimiter, ah(async (req, res) => {
  if (!config.adminJwtSecret) throw new HttpError(503, 'The admin API is not switched on for this server.');
  const { email, password } = parse(z.object({ email: z.string().email().max(200), password: z.string().min(1).max(200) }), req.body);
  const { rows } = await query('select * from admins where lower(email) = lower($1)', [email]);
  const a = rows[0];
  const who = { admin: { id: a?.id ?? null, name: a?.display_name ?? email } };

  if (!a) {
    await dummyVerify(password);
    await audit(req, 'auth.login_failed', { actor: who.admin, details: { email, reason: 'unknown email' } });
    throw new HttpError(401, 'Incorrect email or password.');
  }
  if (a.locked_until && new Date(a.locked_until) > new Date()) {
    const mins = Math.ceil((new Date(a.locked_until) - Date.now()) / 60_000);
    await audit(req, 'auth.login_blocked', { actor: who.admin, details: { reason: 'locked' } });
    throw new HttpError(423, `Too many wrong passwords. This account is locked for ${mins} more minute${mins === 1 ? '' : 's'}.`);
  }
  const ok = await verifyPassword(password, a.password_hash);
  if (!ok || a.disabled) {
    if (!ok) {
      const fails = a.failed_attempts + 1;
      await query(
        'update admins set failed_attempts = case when $2::int >= $3::int then 0 else $2::int end, locked_until = case when $2::int >= $3::int then now() + make_interval(mins => $4::int) else locked_until end where id = $1',
        [a.id, fails, MAX_FAILS, LOCK_MIN],
      );
    }
    await audit(req, 'auth.login_failed', { actor: who.admin, details: { reason: a.disabled ? 'disabled' : 'wrong password' } });
    throw new HttpError(401, a.disabled ? 'This admin account is disabled.' : 'Incorrect email or password.');
  }

  await query('update admins set failed_attempts = 0, locked_until = null, last_login_at = now() where id = $1', [a.id]);
  const s = await query('insert into admin_sessions (admin_id, ip, user_agent) values ($1, $2, $3) returning id', [a.id, req.ip, String(req.headers['user-agent'] ?? '').slice(0, 200)]);
  const token = await signToken(a, s.rows[0].id);
  await audit(req, 'auth.login', { actor: { id: a.id, name: a.display_name }, details: { role: a.role } });
  res.json({ token, admin: publicAdmin(a) });
}));

sessionRoutes.use(requireAdmin);

sessionRoutes.get('/auth/me', ah(async (req, res) => {
  res.json({ admin: publicAdmin(req.admin) });
}));

sessionRoutes.post('/auth/logout', ah(async (req, res) => {
  await query('update admin_sessions set revoked_at = now() where id = $1', [req.admin.sid]);
  await audit(req, 'auth.logout');
  res.status(204).end();
}));

sessionRoutes.post('/auth/password', ah(async (req, res) => {
  const { current, next } = parse(z.object({ current: z.string().min(1).max(200), next: z.string().min(10, 'Use at least 10 characters.').max(200) }), req.body);
  const { rows } = await query('select password_hash from admins where id = $1', [req.admin.id]);
  if (!(await verifyPassword(current, rows[0].password_hash))) throw new HttpError(400, 'Your current password is not right.');
  if (current === next) throw new HttpError(400, 'Pick a password you have not used just now.');
  await query('update admins set password_hash = $2, must_change_password = false where id = $1', [req.admin.id, await hashPassword(next)]);
  // every other session of this admin ends
  await query('update admin_sessions set revoked_at = now() where admin_id = $1 and id <> $2 and revoked_at is null', [req.admin.id, req.admin.sid]);
  await audit(req, 'auth.password_changed');
  res.status(204).end();
}));

// what the app needs to build forms and previews
sessionRoutes.get('/meta', ah(async (req, res) => {
  const s = await getSettings();
  res.json({
    admin: publicAdmin(req.admin),
    envelopes: ENVELOPES,
    templates: s.templates,
    restrictBaseHours: s.restrictBaseHours,
    restrictMaxHours: s.restrictMaxHours,
    strikeAutoRestrictAt: s.strikeAutoRestrictAt,
    strikeAutoBanAt: s.strikeAutoBanAt,
    notifyRestricted: s.notifyRestricted,
    sessionIdleMinutes: s.sessionIdleMinutes,
  });
}));
