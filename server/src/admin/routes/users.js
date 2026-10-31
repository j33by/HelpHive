import { Router } from 'express';
import { z } from 'zod';
import { query } from '../../db.js';
import { admin as sb } from '../../supabase.js';
import { ah, HttpError, parse, uuid } from '../../util.js';
import { effective } from '../../standing.js';
import { audit } from '../log.js';
import { can, generatePassword, requirePerm } from '../auth.js';
import { authIndex, dropAuthIndex, publicUrl, safeTerm } from '../directory.js';
import { changeEmail, changePassword, deleteAccount, loadUser, nextRestriction, perform, removeComment, removePost, standingOf } from '../moderation.js';

const r = Router();
const PAGE = 25;
const ctxOf = (req) => ({ adminId: req.admin.id, adminName: req.admin.name });

const shapeStanding = (row) => {
  const e = effective(row);
  return { status: e.status, until: e.until, strikes: e.strikes, reason: e.reason };
};

// ---------------------------------------------------------------------------
// directory
// ---------------------------------------------------------------------------
r.get('/users', requirePerm('users.view'), ah(async (req, res) => {
  const q = parse(z.object({
    q: z.string().max(80).optional(),
    status: z.enum(['all', 'active', 'restricted', 'banned', 'struck']).default('all'),
    sort: z.enum(['newest', 'oldest', 'name']).default('newest'),
    page: z.coerce.number().int().min(1).max(10000).default(1),
  }), req.query);

  const index = await authIndex();
  const term = safeTerm(q.q);

  let query_ = sb.from('profiles').select('id, username, full_name, avatar_url, created_at', { count: 'exact' });

  if (term) {
    const emailIds = [...index.entries()].filter(([, v]) => v.email.toLowerCase().includes(term.toLowerCase())).map(([id]) => id).slice(0, 100);
    const parts = [`username.ilike.%${term}%`, `full_name.ilike.%${term}%`];
    if (emailIds.length) parts.push(`id.in.(${emailIds.join(',')})`);
    if (/^[0-9a-f-]{36}$/i.test(term)) parts.push(`id.eq.${term}`);
    query_ = query_.or(parts.join(','));
  }

  if (q.status !== 'all') {
    const { data } = await sb.from('user_standing').select('user_id, status, restricted_until, strikes');
    const now = Date.now();
    const rows = data ?? [];
    const ids = rows.filter((x) => {
      if (q.status === 'banned') return x.status === 'banned';
      if (q.status === 'restricted') return x.status === 'restricted' && x.restricted_until && new Date(x.restricted_until) > now;
      if (q.status === 'struck') return x.strikes > 0;
      return false;
    }).map((x) => x.user_id);
    if (q.status === 'active') {
      const bad = rows.filter((x) => x.status === 'banned' || (x.status === 'restricted' && new Date(x.restricted_until) > now)).map((x) => x.user_id);
      if (bad.length) query_ = query_.not('id', 'in', `(${bad.join(',')})`);
    } else {
      if (!ids.length) return res.json({ users: [], total: 0, page: q.page, pageSize: PAGE });
      query_ = query_.in('id', ids);
    }
  }

  const order = { newest: ['created_at', false], oldest: ['created_at', true], name: ['username', true] }[q.sort];
  const from = (q.page - 1) * PAGE;
  const { data: profiles, count, error } = await query_.order(order[0], { ascending: order[1] }).range(from, from + PAGE - 1);
  if (error) throw new HttpError(502, 'Could not read the user list.');

  const ids = profiles.map((p) => p.id);
  const [standings, presence] = await Promise.all([
    ids.length ? sb.from('user_standing').select('*').in('user_id', ids) : { data: [] },
    ids.length ? query('select user_id, last_seen_at, login_count from user_presence where user_id = any($1::uuid[])', [ids]) : { rows: [] },
  ]);
  const st = new Map((standings.data ?? []).map((x) => [x.user_id, x]));
  const pr = new Map(presence.rows.map((x) => [x.user_id, x]));

  res.json({
    total: count ?? 0,
    page: q.page,
    pageSize: PAGE,
    users: profiles.map((p) => ({
      id: p.id,
      username: p.username,
      fullName: p.full_name,
      avatarUrl: p.avatar_url,
      email: index.get(p.id)?.email ?? '',
      createdAt: p.created_at,
      lastSignInAt: index.get(p.id)?.lastSignInAt ?? null,
      lastSeenAt: pr.get(p.id)?.last_seen_at ?? null,
      standing: shapeStanding(st.get(p.id)),
    })),
  });
}));

// ---------------------------------------------------------------------------
// one person
// ---------------------------------------------------------------------------
r.get('/users/:id', requirePerm('users.view'), ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const { data: p, error } = await sb.from('profiles').select('*').eq('id', id).maybeSingle();
  if (error) throw new HttpError(502, 'Could not read the profile.');
  if (!p) throw new HttpError(404, 'That account does not exist.');

  const [authRes, standing, postsC, friendsC, commentsC, presence, logins, actions, notes, reports, appeals, nextR] = await Promise.all([
    sb.auth.admin.getUserById(id),
    standingOf(id),
    sb.from('posts').select('id', { count: 'exact', head: true }).eq('author_id', id),
    sb.from('friendships').select('id', { count: 'exact', head: true }).eq('status', 'accepted').or(`requester_id.eq.${id},addressee_id.eq.${id}`),
    query('select count(*)::int as n from comments where user_id = $1', [id]),
    query('select * from user_presence where user_id = $1', [id]),
    query('select created_at, platform from login_events where user_id = $1 order by created_at desc limit 20', [id]),
    query('select * from moderation_actions where user_id = $1 order by created_at desc limit 200', [id]),
    query('select * from user_notes where user_id = $1 order by created_at desc limit 50', [id]),
    query("select count(*)::int as n, count(*) filter (where status = 'open')::int as open from reports where target_user_id = $1", [id]),
    query('select * from appeals where user_id = $1 order by created_at desc limit 5', [id]),
    nextRestriction(id),
  ]);
  const au = authRes.data?.user;

  await audit(req, 'user.view', { targetType: 'user', targetId: id, targetLabel: `@${p.username}` });

  res.json({
    user: {
      id, username: p.username, fullName: p.full_name, bio: p.bio, location: p.location,
      avatarUrl: p.avatar_url, coverUrl: p.cover_url, createdAt: p.created_at,
      email: au?.email ?? '', emailConfirmed: Boolean(au?.email_confirmed_at),
      provider: au?.app_metadata?.provider ?? 'email',
      lastSignInAt: au?.last_sign_in_at ?? null,
    },
    standing: {
      ...shapeStanding(standing.row),
      bannedAt: standing.now.bannedAt,
      nextRestrictionHours: nextR.hours,
      restrictionLevel: nextR.level,
    },
    counts: {
      posts: postsC.count ?? 0,
      comments: commentsC.rows[0].n,
      friends: friendsC.count ?? 0,
      reports: reports.rows[0].n,
      openReports: reports.rows[0].open,
      logins: presence.rows[0]?.login_count ?? 0,
    },
    presence: { lastSeenAt: presence.rows[0]?.last_seen_at ?? null, lastLoginAt: presence.rows[0]?.last_login_at ?? null },
    logins: logins.rows,
    actions: actions.rows.map(shapeAction),
    notes: notes.rows.map((n) => ({ id: n.id, body: n.body, adminName: n.admin_name, createdAt: n.created_at })),
    appeals: appeals.rows.map((a) => ({ id: a.id, message: a.message, status: a.status, createdAt: a.created_at, decisionReason: a.decision_reason })),
  });
}));

export const shapeAction = (a) => ({
  id: a.id,
  userId: a.user_id,
  username: a.username,
  adminId: a.admin_id,
  adminName: a.admin_name,
  type: a.type,
  reason: a.reason,
  note: a.note,
  message: a.message,
  notified: a.notified,
  auto: a.auto,
  meta: a.meta,
  reversible: a.reversible,
  parentId: a.parent_id,
  createdAt: a.created_at,
  endedAt: a.ended_at,
  revertedAt: a.reverted_at,
  revertedName: a.reverted_name,
  revertReason: a.revert_reason,
  hasSnapshot: Boolean(a.snapshot),
});

r.get('/users/:id/posts', requirePerm('content.view'), ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const page = parse(z.coerce.number().int().min(1).default(1), req.query.page);
  const from = (page - 1) * 20;
  const { data, count, error } = await sb.from('posts').select('*', { count: 'exact' }).eq('author_id', id).order('created_at', { ascending: false }).range(from, from + 19);
  if (error) throw new HttpError(502, 'Could not read the posts.');
  const ids = data.map((p) => p.id);
  const { rows } = ids.length ? await query('select post_id, count(*)::int as n from comments where post_id = any($1::uuid[]) group by post_id', [ids]) : { rows: [] };
  const cc = new Map(rows.map((x) => [x.post_id, x.n]));
  res.json({
    total: count ?? 0,
    posts: data.map((p) => ({ id: p.id, body: p.body, category: p.category, resolved: p.is_resolved, imageUrl: publicUrl(p.image_path), createdAt: p.created_at, comments: cc.get(p.id) ?? 0 })),
  });
}));

r.get('/users/:id/comments', requirePerm('content.view'), ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const page = parse(z.coerce.number().int().min(1).default(1), req.query.page);
  const { rows } = await query('select id, post_id, parent_id, body, created_at, is_helpful from comments where user_id = $1 order by created_at desc limit 20 offset $2', [id, (page - 1) * 20]);
  const total = await query('select count(*)::int as n from comments where user_id = $1', [id]);
  const ids = [...new Set(rows.map((x) => x.post_id))];
  const { data: posts } = ids.length ? await sb.from('posts').select('id, body').in('id', ids) : { data: [] };
  const pb = new Map((posts ?? []).map((p) => [p.id, p.body]));
  res.json({
    total: total.rows[0].n,
    comments: rows.map((c) => ({ id: c.id, postId: c.post_id, isReply: Boolean(c.parent_id), body: c.body, helpful: c.is_helpful, createdAt: c.created_at, postExcerpt: (pb.get(c.post_id) ?? '(post removed)').slice(0, 90) })),
  });
}));

// a mixed timeline: what this person did and what was done to them
r.get('/users/:id/activity', requirePerm('users.view'), ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const [posts, comments, logins, actions] = await Promise.all([
    sb.from('posts').select('id, body, category, created_at').eq('author_id', id).order('created_at', { ascending: false }).limit(30),
    query('select id, body, created_at from comments where user_id = $1 order by created_at desc limit 30', [id]),
    query('select created_at, platform from login_events where user_id = $1 order by created_at desc limit 30', [id]),
    query('select * from moderation_actions where user_id = $1 order by created_at desc limit 30', [id]),
  ]);
  const ev = [
    ...(posts.data ?? []).map((p) => ({ kind: 'post', at: p.created_at, text: p.body.slice(0, 120), meta: p.category })),
    ...comments.rows.map((c) => ({ kind: 'comment', at: c.created_at, text: c.body.slice(0, 120) })),
    ...logins.rows.map((l) => ({ kind: 'login', at: l.created_at, text: `Opened the app${l.platform ? ` (${l.platform})` : ''}` })),
    ...actions.rows.map((a) => ({ kind: 'action', at: a.created_at, text: a.type, meta: a.reason, by: a.admin_name, reverted: Boolean(a.reverted_at) })),
  ].sort((x, y) => new Date(y.at) - new Date(x.at)).slice(0, 80);
  res.json({ events: ev });
}));

// ---------------------------------------------------------------------------
// actions on a person
// ---------------------------------------------------------------------------
const reasonSchema = z.object({ reason: z.string().max(600), note: z.string().max(500).optional() });
const ACTION_PERM = { warn: 'warn', restrict: 'restrict', unrestrict: 'unrestrict', ban: 'ban', unban: 'unban', strike: 'strike', remove_strike: 'remove_strike' };

r.post('/users/:id/actions', ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const body = parse(reasonSchema.extend({ type: z.enum(Object.keys(ACTION_PERM)) }), req.body);
  const perm = ACTION_PERM[body.type];
  if (!can(req.admin, perm)) throw new HttpError(403, 'Your role is not allowed to do that.');

  const out = await perform(ctxOf(req), id, body.type, { reason: body.reason, note: body.note });
  const main = out.actions[0];
  for (const a of out.actions) {
    await audit(req, `user.${a.type}`, {
      targetType: 'user', targetId: id, targetLabel: `@${a.username}`,
      details: { actionId: a.id, reason: a.reason, notified: a.notified, auto: a.auto, ...(a.meta ?? {}) },
    });
  }
  res.status(201).json({ action: shapeAction(main), also: out.actions.slice(1).map(shapeAction), delivered: main.notified });
}));

r.post('/users/:id/email', requirePerm('account.email'), ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const body = parse(reasonSchema.extend({ email: z.string().email().max(200).transform((e) => e.toLowerCase()) }), req.body);
  const a = await changeEmail(ctxOf(req), id, body.email, body.reason, body.note);
  dropAuthIndex();
  await audit(req, 'user.email_change', { targetType: 'user', targetId: id, targetLabel: `@${a.username}`, details: { from: a.meta.from, to: a.meta.to, reason: a.reason, notified: a.notified } });
  res.status(201).json({ action: shapeAction(a) });
}));

r.post('/users/:id/password', requirePerm('account.password'), ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const body = parse(reasonSchema.extend({ password: z.string().min(8, 'Use at least 8 characters.').max(100).optional(), generate: z.boolean().optional() }), req.body);
  if (!body.password && !body.generate) throw new HttpError(400, 'Type a new password or choose Generate.');
  const password = body.generate ? generatePassword() : body.password;
  const a = await changePassword(ctxOf(req), id, password, body.reason, body.note);
  await audit(req, 'user.password_change', { targetType: 'user', targetId: id, targetLabel: `@${a.username}`, details: { reason: a.reason, notified: a.notified, generated: Boolean(body.generate) } });
  // the only time the password is shown; the admin app displays it once
  res.status(201).json({ action: shapeAction(a), password: body.generate ? password : undefined });
}));

r.delete('/users/:id', requirePerm('account.delete'), ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const body = parse(reasonSchema.extend({ confirm: z.string().max(60) }), req.body);
  const user = await loadUser(id);
  if (body.confirm.trim().toLowerCase() !== user.username.toLowerCase()) throw new HttpError(400, 'Type the username exactly to confirm.');
  const a = await deleteAccount(ctxOf(req), id, body.reason, body.note);
  dropAuthIndex();
  await audit(req, 'user.account_delete', { targetType: 'user', targetId: id, targetLabel: `@${user.username}`, details: { reason: a.reason, email: a.meta.email, posts: a.meta.posts } });
  res.status(204).end();
}));

// ---------------------------------------------------------------------------
// notes (admins only, never shown to the person)
// ---------------------------------------------------------------------------
r.post('/users/:id/notes', requirePerm('notes'), ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const { body } = parse(z.object({ body: z.string().trim().min(1, 'Write a note first.').max(1000) }), req.body);
  const user = await loadUser(id);
  const { rows } = await query('insert into user_notes (user_id, admin_id, admin_name, body) values ($1,$2,$3,$4) returning *', [id, req.admin.id, req.admin.name, body]);
  await audit(req, 'user.note_add', { targetType: 'user', targetId: id, targetLabel: `@${user.username}`, details: { note: body } });
  res.status(201).json({ note: { id: rows[0].id, body, adminName: req.admin.name, createdAt: rows[0].created_at } });
}));

r.delete('/users/:id/notes/:noteId', requirePerm('notes'), ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const noteId = parse(uuid, req.params.noteId);
  const { rows } = await query('select * from user_notes where id = $1 and user_id = $2', [noteId, id]);
  if (!rows[0]) throw new HttpError(404, 'Note not found.');
  if (rows[0].admin_id !== req.admin.id && req.admin.role === 'moderator') throw new HttpError(403, 'You can only remove your own notes.');
  await query('delete from user_notes where id = $1', [noteId]);
  await audit(req, 'user.note_remove', { targetType: 'user', targetId: id, details: { note: rows[0].body, writtenBy: rows[0].admin_name } });
  res.status(204).end();
}));

// ---------------------------------------------------------------------------
// content removal
// ---------------------------------------------------------------------------
r.delete('/posts/:id', requirePerm('content.delete'), ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const body = parse(reasonSchema, req.body);
  const { action, user } = await removePost(ctxOf(req), id, body.reason, body.note);
  await audit(req, 'content.delete_post', { targetType: 'post', targetId: id, targetLabel: `@${user.username}: ${action.meta.excerpt}`, details: { reason: action.reason, notified: action.notified, actionId: action.id } });
  res.json({ action: shapeAction(action) });
}));

r.delete('/comments/:id', requirePerm('content.delete'), ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const body = parse(reasonSchema, req.body);
  const { action, user } = await removeComment(ctxOf(req), id, body.reason, body.note);
  await audit(req, 'content.delete_comment', { targetType: 'comment', targetId: id, targetLabel: `@${user.username}: ${action.meta.excerpt}`, details: { reason: action.reason, notified: action.notified, actionId: action.id } });
  res.json({ action: shapeAction(action) });
}));

export default r;
