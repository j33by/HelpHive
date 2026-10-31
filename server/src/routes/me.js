import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { admin, getPost, loadProfiles } from '../supabase.js';
import { getStanding } from '../standing.js';
import { recordLogin } from '../presence.js';
import { getSettings } from '../admin/settings.js';
import { ah, HttpError, parse, uuid } from '../util.js';

const router = Router();

const LABEL = {
  warn: 'Warning', restrict: 'Restriction', unrestrict: 'Restriction lifted', ban: 'Ban', unban: 'Account reinstated',
  strike: 'Strike', remove_strike: 'Strike removed', delete_post: 'Post removed', delete_comment: 'Comment removed',
};

/**
 * What the app shows on the "account standing" screen and banner. The reason
 * is the one an admin wrote; the admin's name is never included.
 */
router.get('/me/standing', ah(async (req, res) => {
  const me = req.user.id;
  const s = await getStanding(me, { fresh: true });
  if (req.query.launch === '1') {
    recordLogin(me, String(req.query.platform ?? '').slice(0, 20) || null).catch((e) => console.error('login record failed:', e.message));
  }

  const settings = await getSettings();
  const [history, appeal] = await Promise.all([
    query(
      `select type, reason, created_at, meta from moderation_actions
        where user_id = $1 and reverted_at is null and type = any($2::text[])
        order by created_at desc limit 20`,
      [me, Object.keys(LABEL)],
    ),
    query('select status, message, decision_reason, created_at, decided_at from appeals where user_id = $1 order by created_at desc limit 1', [me]),
  ]);
  const a = appeal.rows[0];
  res.json({
    status: s.status,
    until: s.until,
    reason: s.reason,
    strikes: s.strikes,
    strikeLimit: settings.strikeAutoRestrictAt || null,
    history: history.rows.map((h) => ({ type: h.type, label: LABEL[h.type], reason: h.reason, createdAt: h.created_at, until: h.meta?.until ?? null })),
    appeal: a ? { status: a.status, message: a.message, decisionReason: a.decision_reason, createdAt: a.created_at, decidedAt: a.decided_at } : null,
    canAppeal: s.status !== 'active' && (!a || a.status !== 'pending'),
  });
}));

router.post('/me/appeal', ah(async (req, res) => {
  const me = req.user.id;
  const { message } = parse(z.object({ message: z.string().trim().min(5, 'Tell us a little more.').max(1000, 'Keep it under 1000 characters.') }), req.body);
  const s = await getStanding(me, { fresh: true });
  if (s.status === 'active') throw new HttpError(400, 'Your account is in good standing.');
  const pending = await query("select 1 from appeals where user_id = $1 and status = 'pending'", [me]);
  if (pending.rows.length) throw new HttpError(409, 'You already have an appeal waiting for review.');
  const p = (await loadProfiles([me])).get(me);
  await query('insert into appeals (user_id, username, message) values ($1, $2, $3)', [me, p?.username ?? '', message]);
  res.status(201).json({ ok: true });
}));

// People can report posts, comments and other people. Admins see them in the Inbox.
router.post('/reports', ah(async (req, res) => {
  const me = req.user.id;
  const body = parse(z.object({
    targetType: z.enum(['post', 'comment', 'user']),
    targetId: uuid,
    reason: z.enum(['spam', 'harassment', 'inappropriate', 'scam', 'misinformation', 'other']),
    details: z.string().trim().max(500).optional(),
  }), req.body);

  let targetUser = null;
  if (body.targetType === 'post') {
    const p = await getPost(body.targetId);
    if (!p) throw new HttpError(404, 'That post no longer exists.');
    targetUser = p.author_id;
  } else if (body.targetType === 'comment') {
    const { rows } = await query('select user_id from comments where id = $1', [body.targetId]);
    if (!rows[0]) throw new HttpError(404, 'That comment no longer exists.');
    targetUser = rows[0].user_id;
  } else {
    const { data } = await admin.from('profiles').select('id').eq('id', body.targetId).maybeSingle();
    if (!data) throw new HttpError(404, 'That person no longer exists.');
    targetUser = data.id;
  }
  if (targetUser === me) throw new HttpError(400, 'You cannot report yourself.');

  try {
    await query(
      'insert into reports (reporter_id, target_type, target_id, target_user_id, reason, details) values ($1,$2,$3,$4,$5,$6)',
      [me, body.targetType, body.targetId, targetUser, body.reason, body.details ?? null],
    );
  } catch (err) {
    if (err.code === '23505') return res.status(204).end(); // already reported; stay quiet
    throw err;
  }
  res.status(201).json({ ok: true });
}));

export default router;
