import { query } from '../db.js';
import { admin as sb } from '../supabase.js';
import { HttpError, SYSTEM_ACTOR } from '../util.js';
import { purgeUser } from '../purge.js';
import { effective, forgetStanding } from '../standing.js';
import { ENVELOPES, fill, fmtUntil, getSettings, hoursLabel } from './settings.js';

/**
 * The one place where a person's standing changes. Routes call perform() and
 * undo(); both write the Supabase standing row (what the database enforces),
 * the Neon history row (what the Control tab undoes) and, when allowed, the
 * notice the person reads in their alerts.
 *
 * ctx = { adminId, adminName }
 */

const REVERSIBLE = new Set(['warn', 'restrict', 'unrestrict', 'ban', 'unban', 'strike', 'remove_strike', 'delete_post', 'delete_comment', 'email_change']);

export const reasonOk = (reason) => {
  const r = String(reason ?? '').trim();
  if (r.length < 8) throw new HttpError(400, 'Write a reason of at least 8 characters. The person will read it.');
  if (r.length > 500) throw new HttpError(400, 'Keep the reason under 500 characters.');
  return r;
};

// ---------------------------------------------------------------------------
// reading
// ---------------------------------------------------------------------------
export async function loadUser(id) {
  const { data, error } = await sb.from('profiles').select('id, username, full_name, avatar_url, created_at').eq('id', id).maybeSingle();
  if (error) throw new HttpError(502, 'Could not reach the profile service.');
  if (!data) throw new HttpError(404, 'That account does not exist (it may have been deleted).');
  return data;
}

async function standingRow(id) {
  const { data, error } = await sb.from('user_standing').select('*').eq('user_id', id).maybeSingle();
  if (error) throw new HttpError(502, 'Could not read the account standing. Has the Supabase schema been updated?');
  return data;
}

async function setStanding(id, patch) {
  const { error } = await sb.from('user_standing').upsert({ user_id: id, ...patch, updated_at: new Date().toISOString() }, { onConflict: 'user_id' });
  if (error) throw new HttpError(502, `Could not update the account standing (${error.message}).`);
  forgetStanding(id);
}

export const standingOf = async (id) => {
  const row = await standingRow(id);
  return { row, now: effective(row) };
};

// ---------------------------------------------------------------------------
// notices
// ---------------------------------------------------------------------------
/**
 * Puts a notice in the person's alerts. People who are banned never see alerts
 * (their screen shows the ban and its reason), and people who are restricted are
 * skipped unless the owner turned that on, as long as `force` is not set.
 */
export async function deliver(userId, type, message, { snippet = null, meta = {}, force = false } = {}) {
  const s = await getSettings();
  const st = effective(await standingRow(userId));
  if (!force) {
    if (st.status === 'banned') return false;
    if (st.status === 'restricted' && !s.notifyRestricted) return false;
  }
  await query(
    `insert into notifications (user_id, actor_id, type, snippet, message, meta)
     values ($1, $2, $3, $4, $5, $6::jsonb)`,
    [userId, SYSTEM_ACTOR, `mod_${type}`, snippet ? snippet.slice(0, 140) : null, message, JSON.stringify(meta)],
  );
  return true;
}

export const compose = (type, vars) => fill(ENVELOPES[type], vars);

// ---------------------------------------------------------------------------
// history rows
// ---------------------------------------------------------------------------
async function record(ctx, user, type, { reason, note = null, message = null, notified = false, auto = false, meta = {}, snapshot = null, parentId = null }) {
  const { rows } = await query(
    `insert into moderation_actions
       (user_id, username, admin_id, admin_name, type, reason, note, message, notified, auto, meta, snapshot, reversible, parent_id)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb,$12::jsonb,$13,$14)
     returning *`,
    [user.id, user.username, ctx.adminId, ctx.adminName, type, reason, note, message, notified, auto,
      JSON.stringify(meta), snapshot ? JSON.stringify(snapshot) : null, REVERSIBLE.has(type), parentId],
  );
  return rows[0];
}

const endOpen = (userId, type, adminId) =>
  query(
    `update moderation_actions set ended_at = now()
      where user_id = $1 and type = $2 and ended_at is null and reverted_at is null`,
    [userId, type],
  );

async function restrictionLevel(userId) {
  const { rows } = await query("select count(*)::int as n from moderation_actions where user_id = $1 and type = 'restrict' and reverted_at is null", [userId]);
  return rows[0].n;
}

export async function nextRestriction(userId) {
  const s = await getSettings();
  const prior = await restrictionLevel(userId);
  const hours = Math.min(s.restrictBaseHours * (prior + 1), s.restrictMaxHours);
  return { level: prior + 1, hours };
}

// ---------------------------------------------------------------------------
// perform
// ---------------------------------------------------------------------------
export async function perform(ctx, userId, type, { reason, note = null, auto = false, parentId = null } = {}) {
  reason = reasonOk(reason);
  const user = await loadUser(userId);
  const { row, now } = await standingOf(userId);
  const settings = await getSettings();
  const out = { actions: [] };

  switch (type) {
    case 'warn': {
      if (now.status === 'banned') throw new HttpError(409, 'This account is banned. A warning would never be seen.');
      const message = compose('warn', { reason });
      const sent = await deliver(userId, 'warn', message, { snippet: reason, meta: { action: 'warn' } });
      out.actions.push(await record(ctx, user, 'warn', { reason, note, message, notified: sent, auto, parentId }));
      break;
    }

    case 'restrict': {
      if (now.status === 'banned') throw new HttpError(409, 'This account is already banned.');
      if (now.status === 'restricted') throw new HttpError(409, `Already restricted until ${fmtUntil(now.until)}. Lift it first if you want to start a new one.`);
      const { level, hours } = await nextRestriction(userId);
      const until = new Date(Date.now() + hours * 3_600_000);
      const message = compose('restrict', { duration: hoursLabel(hours), until: fmtUntil(until), reason });
      // the notice goes out first and always: it is how the person learns why
      const sent = await deliver(userId, 'restrict', message, { snippet: reason, meta: { action: 'restrict', until: until.toISOString(), hours, level }, force: true });
      await setStanding(userId, { status: 'restricted', restricted_until: until.toISOString(), reason });
      out.actions.push(await record(ctx, user, 'restrict', { reason, note, message, notified: sent, auto, parentId, meta: { hours, level, until: until.toISOString() } }));
      break;
    }

    case 'unrestrict': {
      if (now.status !== 'restricted') throw new HttpError(409, 'This account is not restricted.');
      await setStanding(userId, { status: 'active', restricted_until: null, reason: null });
      await endOpen(userId, 'restrict');
      const message = compose('unrestrict', { reason });
      const sent = await deliver(userId, 'unrestrict', message, { snippet: reason, meta: { action: 'unrestrict' } });
      out.actions.push(await record(ctx, user, 'unrestrict', { reason, note, message, notified: sent, auto, parentId, meta: { previousUntil: now.until } }));
      break;
    }

    case 'ban': {
      if (now.status === 'banned') throw new HttpError(409, 'This account is already banned.');
      await setStanding(userId, { status: 'banned', restricted_until: null, reason, banned_at: new Date().toISOString() });
      await endOpen(userId, 'restrict');
      // no notice: a banned person only sees the ban screen, with the reason on it
      out.actions.push(await record(ctx, user, 'ban', { reason, note, message: compose('ban', { reason }), notified: false, auto, parentId }));
      break;
    }

    case 'unban': {
      if (now.status !== 'banned') throw new HttpError(409, 'This account is not banned.');
      const { rows } = await query("select reason from moderation_actions where user_id = $1 and type = 'ban' and ended_at is null and reverted_at is null order by created_at desc limit 1", [userId]);
      await setStanding(userId, { status: 'active', restricted_until: null, reason: null, banned_at: null });
      await endOpen(userId, 'ban');
      const message = compose('unban', { reason });
      const sent = await deliver(userId, 'unban', message, { snippet: reason, meta: { action: 'unban' } });
      out.actions.push(await record(ctx, user, 'unban', { reason, note, message, notified: sent, auto, parentId, meta: { banReason: rows[0]?.reason ?? row?.reason ?? '' } }));
      break;
    }

    case 'strike': {
      if (now.status === 'banned') throw new HttpError(409, 'This account is banned. Strikes no longer matter.');
      const count = now.strikes + 1;
      await setStanding(userId, { strikes: count });
      const message = compose('strike', { count, reason });
      const sent = await deliver(userId, 'strike', message, { snippet: reason, meta: { action: 'strike', count } });
      const strike = await record(ctx, user, 'strike', { reason, note, message, notified: sent, auto, parentId, meta: { count } });
      out.actions.push(strike);

      // strikes escalate by themselves, using the owner's thresholds
      const banAt = settings.strikeAutoBanAt;
      const restrictAt = settings.strikeAutoRestrictAt;
      if (banAt > 0 && count >= banAt) {
        const sub = await perform(ctx, userId, 'ban', { reason: `Automatic: reached ${count} strikes. Last strike: ${reason}`.slice(0, 500), auto: true, parentId: strike.id });
        out.actions.push(...sub.actions);
      } else if (restrictAt > 0 && count >= restrictAt) {
        const cur = await standingOf(userId);
        if (cur.now.status === 'active') {
          const sub = await perform(ctx, userId, 'restrict', { reason: `Automatic: reached ${count} strikes. Last strike: ${reason}`.slice(0, 500), auto: true, parentId: strike.id });
          out.actions.push(...sub.actions);
        }
      }
      break;
    }

    case 'remove_strike': {
      if (now.strikes < 1) throw new HttpError(409, 'This account has no strikes.');
      const count = now.strikes - 1;
      await setStanding(userId, { strikes: count });
      const message = compose('remove_strike', { count, reason });
      const sent = await deliver(userId, 'remove_strike', message, { snippet: reason, meta: { action: 'remove_strike', count } });
      out.actions.push(await record(ctx, user, 'remove_strike', { reason, note, message, notified: sent, auto, parentId, meta: { count } }));
      break;
    }

    default:
      throw new HttpError(400, 'Unknown action.');
  }
  return out;
}

// ---------------------------------------------------------------------------
// content removal (kept as a snapshot so it can be restored)
// ---------------------------------------------------------------------------
const excerpt = (s, n = 140) => (s.length > n ? `${s.slice(0, n)}…` : s);

export async function removePost(ctx, postId, reason, note = null) {
  reason = reasonOk(reason);
  const { data: post, error } = await sb.from('posts').select('*').eq('id', postId).maybeSingle();
  if (error) throw new HttpError(502, 'Could not read the post.');
  if (!post) throw new HttpError(404, 'That post no longer exists.');
  const user = await loadUser(post.author_id);

  const { data: reactions } = await sb.from('post_reactions').select('*').eq('post_id', postId);
  const { rows: comments } = await query('select * from comments where post_id = $1 order by created_at asc limit 1000', [postId]);

  // the picture stays in storage so the post can be restored; it goes with the account
  const del = await sb.from('posts').delete().eq('id', postId);
  if (del.error) throw new HttpError(502, 'Could not delete the post.');
  await query('delete from notifications where post_id = $1', [postId]);
  await query('delete from comments where post_id = $1', [postId]);
  await query("update reports set status = 'actioned', handled_at = now(), handled_by = $2, handled_name = $3, resolution_note = 'Post removed' where target_type = 'post' and target_id = $1 and status = 'open'", [postId, ctx.adminId, ctx.adminName]);

  const message = compose('delete_post', { reason });
  const sent = await deliver(user.id, 'delete_post', message, { snippet: excerpt(post.body, 80), meta: { action: 'delete_post', reason } });
  const action = await record(ctx, user, 'delete_post', {
    reason, note, message, notified: sent,
    meta: { postId, excerpt: excerpt(post.body), hasImage: Boolean(post.image_path), comments: comments.length },
    snapshot: { post, reactions: reactions ?? [], comments },
  });
  return { action, user };
}

export async function removeComment(ctx, commentId, reason, note = null) {
  reason = reasonOk(reason);
  const { rows } = await query('select * from comments where id = $1', [commentId]);
  const c = rows[0];
  if (!c) throw new HttpError(404, 'That comment no longer exists.');
  const user = await loadUser(c.user_id);
  const { rows: replies } = await query('select * from comments where parent_id = $1 order by created_at asc', [commentId]);
  const ids = [commentId, ...replies.map((r) => r.id)];

  await query('delete from notifications where comment_id = any($1::uuid[])', [ids]);
  await query('delete from comments where id = $1', [commentId]); // replies cascade
  await query("update reports set status = 'actioned', handled_at = now(), handled_by = $2, handled_name = $3, resolution_note = 'Comment removed' where target_type = 'comment' and target_id = $1 and status = 'open'", [commentId, ctx.adminId, ctx.adminName]);

  const message = compose('delete_comment', { reason });
  const sent = await deliver(user.id, 'delete_comment', message, { snippet: excerpt(c.body, 80), meta: { action: 'delete_comment', reason } });
  const action = await record(ctx, user, 'delete_comment', {
    reason, note, message, notified: sent,
    meta: { commentId, postId: c.post_id, excerpt: excerpt(c.body), replies: replies.length },
    snapshot: { comment: c, replies },
  });
  return { action, user };
}

// ---------------------------------------------------------------------------
// account changes
// ---------------------------------------------------------------------------
export async function changeEmail(ctx, userId, email, reason, note = null) {
  reason = reasonOk(reason);
  const user = await loadUser(userId);
  const { data: before, error: e1 } = await sb.auth.admin.getUserById(userId);
  if (e1 || !before?.user) throw new HttpError(502, 'Could not read the account.');
  const old = before.user.email ?? '';
  if (old.toLowerCase() === email.toLowerCase()) throw new HttpError(400, 'That is already the email on this account.');
  const { error } = await sb.auth.admin.updateUserById(userId, { email, email_confirm: true });
  if (error) throw new HttpError(400, /registered|exists/i.test(error.message) ? 'Another account already uses that email.' : `Could not change the email (${error.message}).`);
  const message = compose('email_change', { reason });
  const sent = await deliver(userId, 'email_change', message, { snippet: reason, meta: { action: 'email_change' } });
  return record(ctx, user, 'email_change', { reason, note, message, notified: sent, meta: { from: old, to: email } });
}

export async function changePassword(ctx, userId, password, reason, note = null) {
  reason = reasonOk(reason);
  const user = await loadUser(userId);
  const { error } = await sb.auth.admin.updateUserById(userId, { password });
  if (error) throw new HttpError(400, `Could not change the password (${error.message}).`);
  const message = compose('password_change', { reason });
  const sent = await deliver(userId, 'password_change', message, { snippet: reason, meta: { action: 'password_change' } });
  // the password itself is never stored or logged
  return record(ctx, user, 'password_change', { reason, note, message, notified: sent });
}

export async function deleteAccount(ctx, userId, reason, note = null) {
  reason = reasonOk(reason);
  const user = await loadUser(userId);
  const { data: auth } = await sb.auth.admin.getUserById(userId);
  const { count } = await sb.from('posts').select('id', { count: 'exact', head: true }).eq('author_id', userId);
  // history first: if the purge fails halfway the record still says what was attempted
  const action = await record(ctx, user, 'account_delete', { reason, note, message: null, notified: false, meta: { email: auth?.user?.email ?? null, posts: count ?? 0 } });
  await purgeUser(userId);
  forgetStanding(userId);
  return action;
}

// ---------------------------------------------------------------------------
// undo
// ---------------------------------------------------------------------------
const SUMMARY = {
  warn: 'a warning',
  restrict: 'a restriction',
  unrestrict: 'lifting your restriction',
  ban: 'a ban',
  unban: 'reinstating your account',
  strike: 'a strike',
  remove_strike: 'removing a strike',
  delete_post: 'removing one of your posts',
  delete_comment: 'removing one of your comments',
  email_change: 'an email change',
};

export async function undo(ctx, actionId, reason, { cascade = true } = {}) {
  reason = reasonOk(reason);
  const { rows } = await query('select * from moderation_actions where id = $1', [actionId]);
  const a = rows[0];
  if (!a) throw new HttpError(404, 'Action not found.');
  if (a.reverted_at) throw new HttpError(409, 'That action was already undone.');
  if (!a.reversible) throw new HttpError(409, 'This kind of action cannot be undone.');

  const undone = [];
  // anything this action triggered (automatic restrictions or bans after a strike) goes first
  if (cascade) {
    const kids = await query('select id from moderation_actions where parent_id = $1 and reverted_at is null and reversible order by created_at desc', [a.id]);
    for (const k of kids.rows) undone.push(...(await undo(ctx, k.id, reason, { cascade: true })));
  }

  const userId = a.user_id;
  const m = a.meta ?? {};
  let user = null;
  const needUser = async () => (user ??= await loadUser(userId).catch(() => {
    throw new HttpError(409, 'The account no longer exists, so this cannot be undone.');
  }));
  const state = async () => (await standingOf(userId)).now;

  switch (a.type) {
    case 'warn':
      break;
    case 'restrict': {
      const st = await state();
      if (st.status === 'restricted' && new Date(st.until) <= new Date(new Date(m.until).getTime() + 1000)) {
        await needUser();
        await setStanding(userId, { status: 'active', restricted_until: null, reason: null });
      }
      break;
    }
    case 'unrestrict': {
      await needUser();
      const st = await state();
      if (st.status === 'banned') throw new HttpError(409, 'The account is banned now, so the restriction cannot be put back.');
      if (!m.previousUntil || new Date(m.previousUntil) <= new Date()) throw new HttpError(409, 'That restriction would already have ended, so there is nothing to put back.');
      const { rows: orig } = await query("select reason from moderation_actions where user_id = $1 and type = 'restrict' and reverted_at is null order by created_at desc limit 1", [userId]);
      await setStanding(userId, { status: 'restricted', restricted_until: m.previousUntil, reason: orig[0]?.reason ?? 'Restriction restored after review.' });
      await query("update moderation_actions set ended_at = null where user_id = $1 and type = 'restrict' and reverted_at is null and id = (select id from moderation_actions where user_id = $1 and type = 'restrict' and reverted_at is null order by created_at desc limit 1)", [userId]);
      break;
    }
    case 'ban': {
      const st = await state();
      if (st.status === 'banned') {
        await needUser();
        await setStanding(userId, { status: 'active', restricted_until: null, reason: null, banned_at: null });
      }
      break;
    }
    case 'unban': {
      await needUser();
      const st = await state();
      if (st.status === 'banned') break;
      await setStanding(userId, { status: 'banned', restricted_until: null, reason: m.banReason || 'Ban restored after review.', banned_at: new Date().toISOString() });
      await query("update moderation_actions set ended_at = null where id = (select id from moderation_actions where user_id = $1 and type = 'ban' and reverted_at is null order by created_at desc limit 1)", [userId]);
      break;
    }
    case 'strike': {
      await needUser();
      const st = await state();
      await setStanding(userId, { strikes: Math.max(0, st.strikes - 1) });
      break;
    }
    case 'remove_strike': {
      await needUser();
      const st = await state();
      await setStanding(userId, { strikes: st.strikes + 1 });
      break;
    }
    case 'delete_post': {
      await needUser();
      const snap = a.snapshot;
      if (!snap?.post) throw new HttpError(409, 'The removed post was not kept, so it cannot be restored.');
      const p = snap.post;
      const { error } = await sb.from('posts').insert({
        id: p.id, author_id: p.author_id, body: p.body, image_path: p.image_path, category: p.category,
        is_resolved: p.is_resolved, created_at: p.created_at, updated_at: p.updated_at,
      });
      if (error) throw new HttpError(409, /duplicate/i.test(error.message) ? 'That post already exists again.' : `Could not restore the post (${error.message}).`);
      if (snap.reactions?.length) {
        await sb.from('post_reactions').upsert(snap.reactions.map((r) => ({ post_id: r.post_id, user_id: r.user_id, kind: r.kind, created_at: r.created_at })), { ignoreDuplicates: true });
      }
      await restoreComments(snap.comments ?? []);
      break;
    }
    case 'delete_comment': {
      await needUser();
      const snap = a.snapshot;
      if (!snap?.comment) throw new HttpError(409, 'The removed comment was not kept, so it cannot be restored.');
      const post = await sb.from('posts').select('id').eq('id', snap.comment.post_id).maybeSingle();
      if (!post.data) throw new HttpError(409, 'The post this comment belonged to is gone.');
      await restoreComments([snap.comment, ...(snap.replies ?? [])]);
      break;
    }
    case 'email_change': {
      await needUser();
      const { error } = await sb.auth.admin.updateUserById(userId, { email: m.from, email_confirm: true });
      if (error) throw new HttpError(409, `Could not put the old email back (${error.message}).`);
      break;
    }
    default:
      throw new HttpError(409, 'This kind of action cannot be undone.');
  }

  await query(
    `update moderation_actions set reverted_at = now(), reverted_by = $2, reverted_name = $3, revert_reason = $4 where id = $1`,
    [a.id, ctx.adminId, ctx.adminName, reason],
  );

  // let the person know, unless they are banned or restricted (then the standing screen carries it)
  if (needUserSafe(a.type)) {
    const alive = await sb.from('profiles').select('id').eq('id', userId).maybeSingle();
    if (alive.data) {
      const message = compose('revert', { summary: SUMMARY[a.type] ?? 'an earlier action', reason });
      await deliver(userId, 'revert', message, { snippet: reason, meta: { action: 'revert', reverted: a.type } });
    }
  }
  undone.push({ id: a.id, type: a.type, userId, username: a.username });
  return undone;
}

const needUserSafe = (type) => type !== 'email_change';

async function restoreComments(list) {
  const ordered = [...list.filter((c) => !c.parent_id), ...list.filter((c) => c.parent_id)];
  for (const c of ordered) {
    await query(
      `insert into comments (id, post_id, parent_id, user_id, body, edited, created_at, updated_at, is_helpful, helpful_at)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) on conflict (id) do nothing`,
      [c.id, c.post_id, c.parent_id, c.user_id, c.body, c.edited, c.created_at, c.updated_at, c.is_helpful ?? false, c.helpful_at ?? null],
    );
  }
}
