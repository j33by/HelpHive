import crypto from 'node:crypto';
import { promisify } from 'node:util';
import { SignJWT, jwtVerify } from 'jose';
import { config } from '../config.js';
import { query } from '../db.js';
import { ah, HttpError } from '../util.js';
import { getSettings } from './settings.js';

const scrypt = promisify(crypto.scrypt);
const N = 16384;

export async function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const key = await scrypt(password, salt, 64, { N, r: 8, p: 1 });
  return `scrypt$${N}$${salt.toString('base64')}$${key.toString('base64')}`;
}

export async function verifyPassword(password, stored) {
  const [alg, n, salt, key] = String(stored).split('$');
  if (alg !== 'scrypt' || !salt || !key) return false;
  const expected = Buffer.from(key, 'base64');
  const actual = await scrypt(password, Buffer.from(salt, 'base64'), expected.length, { N: Number(n), r: 8, p: 1 });
  return crypto.timingSafeEqual(expected, actual);
}

// compared against when the email is unknown, so "no such admin" costs the same time
const DUMMY = await hashPassword(crypto.randomBytes(8).toString('hex'));
export const dummyVerify = (pw) => verifyPassword(pw, DUMMY);

export const generatePassword = () => crypto.randomBytes(12).toString('base64url');

const key = () => new TextEncoder().encode(config.adminJwtSecret);
const ISS = 'helphive-admin';

export const signToken = (admin, sid) =>
  new SignJWT({ sid, role: admin.role })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(admin.id)
    .setIssuer(ISS)
    .setAudience(ISS)
    .setIssuedAt()
    .setExpirationTime('12h')
    .sign(key());

// ---------------------------------------------------------------------------
// roles
// ---------------------------------------------------------------------------
const MODERATOR = [
  'users.view', 'content.view', 'warn', 'restrict', 'unrestrict', 'strike', 'remove_strike',
  'content.delete', 'notes', 'reports', 'control.own',
];
const ADMIN = [
  ...MODERATOR, 'ban', 'unban', 'account.email', 'account.password', 'account.delete',
  'announce', 'appeals', 'control.all', 'logs', 'system', 'release',
];
const OWNER = [...ADMIN, 'team', 'settings'];

export const ROLE_PERMS = { moderator: MODERATOR, admin: ADMIN, owner: OWNER };
export const can = (admin, perm) => (ROLE_PERMS[admin.role] ?? []).includes(perm);

export const requirePerm = (perm) => (req, _res, next) => {
  if (!can(req.admin, perm)) return next(new HttpError(403, 'Your role is not allowed to do that.'));
  next();
};

// ---------------------------------------------------------------------------
// middleware
// ---------------------------------------------------------------------------
export const requireAdmin = ah(async (req, _res, next) => {
  if (!config.adminJwtSecret) throw new HttpError(503, 'The admin API is not switched on for this server.');
  const m = /^Bearer ([\w-]+\.[\w-]+\.[\w-]+)$/.exec(req.headers.authorization || '');
  if (!m) throw new HttpError(401, 'Please sign in.');

  let payload;
  try {
    ({ payload } = await jwtVerify(m[1], key(), { issuer: ISS, audience: ISS, algorithms: ['HS256'] }));
  } catch {
    throw new HttpError(401, 'Your session has expired. Please sign in again.');
  }

  const { rows } = await query(
    `select s.id as sid, s.last_seen_at, s.revoked_at,
            a.id, a.email, a.display_name, a.role, a.disabled, a.must_change_password
       from admin_sessions s join admins a on a.id = s.admin_id
      where s.id = $1 and a.id = $2`,
    [payload.sid, payload.sub],
  );
  const r = rows[0];
  if (!r || r.revoked_at || r.disabled) throw new HttpError(401, 'This session is no longer valid. Please sign in again.');

  const { sessionIdleMinutes } = await getSettings();
  if (Date.now() - new Date(r.last_seen_at).getTime() > sessionIdleMinutes * 60_000) {
    await query('update admin_sessions set revoked_at = now() where id = $1', [r.sid]);
    throw new HttpError(401, 'You were signed out after being idle. Please sign in again.');
  }
  if (Date.now() - new Date(r.last_seen_at).getTime() > 30_000) {
    query('update admin_sessions set last_seen_at = now() where id = $1', [r.sid]).catch(() => {});
  }

  req.admin = { id: r.id, email: r.email, name: r.display_name, role: r.role, sid: r.sid, mustChangePassword: r.must_change_password };
  next();
});

export const publicAdmin = (a) => ({
  id: a.id,
  email: a.email,
  name: a.name ?? a.display_name,
  role: a.role,
  mustChangePassword: a.mustChangePassword ?? a.must_change_password ?? false,
  permissions: ROLE_PERMS[a.role] ?? [],
});

/** Creates the first owner from environment variables when the admins table is empty. */
export async function bootstrapOwner() {
  if (!config.bootstrapEmail || !config.bootstrapPassword) return;
  try {
    const { rows } = await query('select 1 from admins limit 1');
    if (rows.length) return;
    await query(
      `insert into admins (email, display_name, role, password_hash, must_change_password)
       values ($1, 'Owner', 'owner', $2, true)`,
      [config.bootstrapEmail.trim().toLowerCase(), await hashPassword(config.bootstrapPassword)],
    );
    console.log(`Admin: created the first owner (${config.bootstrapEmail}). Sign in and change the password.`);
  } catch (err) {
    console.error('Admin bootstrap skipped:', err.message);
  }
}
