import { Router } from 'express';
import { z } from 'zod';
import { query } from '../../db.js';
import { admin as sb } from '../../supabase.js';
import { ah, HttpError, parse, SYSTEM_ACTOR, uuid } from '../../util.js';
import { audit } from '../log.js';
import { requirePerm } from '../auth.js';

const r = Router();

const shape = (a) => ({
  id: a.id, kind: a.kind, title: a.title, body: a.body, eventAt: a.event_at, location: a.location,
  pinned: a.pinned, authorName: a.author_name, createdAt: a.created_at, expiresAt: a.expires_at, deletedAt: a.deleted_at,
});

const input = z.object({
  kind: z.enum(['update', 'event', 'alert']),
  title: z.string().trim().min(1, 'Add a title.').max(120),
  body: z.string().trim().max(2000).default(''),
  eventAt: z.string().datetime({ offset: true }).nullable().optional(),
  location: z.string().trim().max(120).nullable().optional(),
  pinned: z.boolean().default(false),
  expiresAt: z.string().datetime({ offset: true }).nullable().optional(),
  notifyAll: z.boolean().default(false),
}).superRefine((v, ctx) => {
  if (v.kind === 'event' && !v.eventAt) ctx.addIssue({ code: 'custom', message: 'Pick a date and time for the event.' });
  if (v.kind !== 'event' && !v.body) ctx.addIssue({ code: 'custom', message: 'Write the update text.' });
});

r.get('/announcements', requirePerm('announce'), ah(async (_req, res) => {
  const { data, error } = await sb.from('announcements').select('*').order('created_at', { ascending: false }).limit(100);
  if (error) throw new HttpError(502, 'Could not read the announcements. Has the Supabase schema been updated?');
  res.json({ announcements: data.map(shape) });
}));

// Notifies every person except banned ones. Done in pages so a big community does not stall.
async function notifyEveryone(title, body, announcementId) {
  const { data: banned } = await sb.from('user_standing').select('user_id').eq('status', 'banned');
  const skip = new Set((banned ?? []).map((b) => b.user_id));
  const message = body ? `${title}\n\n${body}`.slice(0, 600) : title;
  let sent = 0;
  for (let page = 0; page < 50; page++) {
    const { data, error } = await sb.from('profiles').select('id').order('created_at', { ascending: true }).range(page * 1000, page * 1000 + 999);
    if (error) throw new HttpError(502, 'Could not list the people to notify.');
    const ids = data.map((p) => p.id).filter((id) => !skip.has(id));
    if (ids.length) {
      await query(
        `insert into notifications (user_id, actor_id, type, snippet, message, meta)
         select u, $2, 'mod_notice', $3, $4, $5::jsonb from unnest($1::uuid[]) as u`,
        [ids, SYSTEM_ACTOR, title.slice(0, 140), message, JSON.stringify({ announcementId })],
      );
      sent += ids.length;
    }
    if (data.length < 1000) break;
  }
  return sent;
}

r.post('/announcements', requirePerm('announce'), ah(async (req, res) => {
  const v = parse(input, req.body);
  const { data, error } = await sb.from('announcements').insert({
    kind: v.kind, title: v.title, body: v.body, event_at: v.kind === 'event' ? v.eventAt : null,
    location: v.kind === 'event' ? v.location || null : null, pinned: v.pinned, expires_at: v.expiresAt ?? null,
    author_name: 'HelpHive Team',
  }).select('*').single();
  if (error) throw new HttpError(502, `Could not post it (${error.message}).`);
  let notified = 0;
  if (v.notifyAll) notified = await notifyEveryone(v.title, v.body, data.id);
  await audit(req, 'announcement.create', { targetType: 'announcement', targetId: data.id, targetLabel: v.title, details: { kind: v.kind, pinned: v.pinned, notifiedPeople: notified, eventAt: v.eventAt ?? null } });
  res.status(201).json({ announcement: shape(data), notified });
}));

r.put('/announcements/:id', requirePerm('announce'), ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const v = parse(input, req.body);
  const { data, error } = await sb.from('announcements').update({
    kind: v.kind, title: v.title, body: v.body, event_at: v.kind === 'event' ? v.eventAt : null,
    location: v.kind === 'event' ? v.location || null : null, pinned: v.pinned, expires_at: v.expiresAt ?? null,
    updated_at: new Date().toISOString(),
  }).eq('id', id).is('deleted_at', null).select('*').maybeSingle();
  if (error) throw new HttpError(502, 'Could not save the changes.');
  if (!data) throw new HttpError(404, 'That announcement is gone.');
  await audit(req, 'announcement.update', { targetType: 'announcement', targetId: id, targetLabel: v.title, details: { kind: v.kind, pinned: v.pinned } });
  res.json({ announcement: shape(data) });
}));

r.delete('/announcements/:id', requirePerm('announce'), ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  const { data, error } = await sb.from('announcements').update({ deleted_at: new Date().toISOString() }).eq('id', id).is('deleted_at', null).select('title').maybeSingle();
  if (error) throw new HttpError(502, 'Could not remove it.');
  if (!data) throw new HttpError(404, 'That announcement is gone.');
  await audit(req, 'announcement.delete', { targetType: 'announcement', targetId: id, targetLabel: data.title });
  res.status(204).end();
}));

export default r;
