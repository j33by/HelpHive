import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { loadProfiles, profileExists } from '../supabase.js';
import { ah, cursor, HttpError, parse, reactionKind, text, uuid } from '../util.js';

const router = Router();

// A pair of people has one conversation; user_a is the smaller uuid.
const pairOf = (x, y) => (x < y ? [x, y] : [y, x]);

async function loadConversation(id, me) {
  const { rows } = await query(
    'select * from conversations where id = $1 and (user_a = $2 or user_b = $2)',
    [id, me],
  );
  // Same answer for "does not exist" and "not yours" so ids cannot be probed.
  if (!rows[0]) throw new HttpError(404, 'Conversation not found.');
  return rows[0];
}

// People I have actually exchanged messages with, newest first.
router.get('/conversations', ah(async (req, res) => {
  const me = req.user.id;
  const { rows } = await query(
    `select c.id, c.last_message_at,
            case when c.user_a = $1 then c.user_b else c.user_a end as other_id,
            lm.id as last_id, lm.body as last_body, lm.sender_id as last_sender, (lm.deleted_at is not null) as last_deleted,
            (select count(*)::int from messages m
               where m.conversation_id = c.id and m.sender_id <> $1 and m.deleted_at is null
                 and m.created_at > case when c.user_a = $1 then c.a_read_at else c.b_read_at end) as unread
       from conversations c
       join lateral (select * from messages m where m.conversation_id = c.id
                      order by m.created_at desc limit 1) lm on true
      where c.user_a = $1 or c.user_b = $1
      order by c.last_message_at desc
      limit 100`,
    [me],
  );
  const users = await loadProfiles(rows.map((r) => r.other_id));
  res.json({
    conversations: rows.map((r) => ({
      id: r.id,
      user: users.get(r.other_id),
      lastMessage: {
        id: r.last_id,
        body: r.last_deleted ? '' : r.last_body.slice(0, 120),
        mine: r.last_sender === me,
        deleted: r.last_deleted,
      },
      lastMessageAt: r.last_message_at,
      unread: r.unread,
    })),
  });
}));

// Open (or create) the conversation with someone.
router.post('/conversations', ah(async (req, res) => {
  const me = req.user.id;
  const { userId } = parse(z.object({ userId: uuid }), req.body);
  if (userId === me) throw new HttpError(400, "You can't message yourself.");
  if (!(await profileExists(userId))) throw new HttpError(404, 'That person could not be found.');

  const [a, b] = pairOf(me, userId);
  const { rows } = await query(
    `insert into conversations (user_a, user_b) values ($1, $2)
     on conflict (user_a, user_b) do update set user_a = excluded.user_a
     returning id`,
    [a, b],
  );
  res.json({ id: rows[0].id });
}));

router.get('/conversations/:id/messages', ah(async (req, res) => {
  const me = req.user.id;
  const id = parse(uuid, req.params.id);
  const { before } = parse(z.object({ before: cursor }), req.query);
  const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 50, 1), 100);
  const conv = await loadConversation(id, me);

  const { rows } = await query(
    `select m.id, m.sender_id, m.created_at, (m.deleted_at is not null) as deleted,
            case when m.deleted_at is null then m.body else '' end as body,
            m.reply_to,
            case when rm.deleted_at is null then left(rm.body, 120) else '' end as reply_body,
            rm.sender_id as reply_sender, (rm.deleted_at is not null) as reply_deleted,
            coalesce((select jsonb_object_agg(x.kind, x.n)
                        from (select kind, count(*)::int as n from message_reactions
                               where message_id = m.id group by kind) x), '{}'::jsonb) as reactions,
            (select kind from message_reactions where message_id = m.id and user_id = $2) as my_reaction
       from messages m
       left join messages rm on rm.id = m.reply_to
      where m.conversation_id = $1 and ($3::timestamptz is null or m.created_at < $3::timestamptz)
      order by m.created_at desc
      limit $4`,
    [id, me, before ?? null, limit + 1],
  );

  const hasMore = rows.length > limit;
  const page = rows.slice(0, limit).reverse();
  res.json({
    messages: page.map((r) => ({
      id: r.id,
      conversationId: id,
      senderId: r.sender_id,
      body: r.body,
      deleted: r.deleted,
      createdAt: r.created_at,
      replyTo: r.reply_to
        ? { id: r.reply_to, body: r.reply_body ?? '', senderId: r.reply_sender, deleted: Boolean(r.reply_deleted) }
        : null,
      reactions: r.reactions,
      myReaction: r.my_reaction ?? null,
    })),
    hasMore,
    otherReadAt: conv.user_a === me ? conv.b_read_at : conv.a_read_at,
  });
}));

router.post('/conversations/:id/messages', ah(async (req, res) => {
  const me = req.user.id;
  const id = parse(uuid, req.params.id);
  const { body, replyTo } = parse(z.object({ body: text(2000), replyTo: uuid.nullish() }), req.body);
  const conv = await loadConversation(id, me);

  if (replyTo) {
    const { rowCount } = await query('select 1 from messages where id = $1 and conversation_id = $2', [replyTo, id]);
    if (!rowCount) throw new HttpError(404, 'The message you are replying to is gone.');
  }

  const { rows } = await query(
    'insert into messages (conversation_id, sender_id, body, reply_to) values ($1, $2, $3, $4) returning id, created_at',
    [id, me, body, replyTo ?? null],
  );
  const readCol = conv.user_a === me ? 'a_read_at' : 'b_read_at';
  await query(`update conversations set last_message_at = $2, ${readCol} = $2 where id = $1`, [id, rows[0].created_at]);

  res.status(201).json({ id: rows[0].id, createdAt: rows[0].created_at });
}));

router.post('/conversations/:id/read', ah(async (req, res) => {
  const me = req.user.id;
  const id = parse(uuid, req.params.id);
  const conv = await loadConversation(id, me);
  const readCol = conv.user_a === me ? 'a_read_at' : 'b_read_at';
  await query(`update conversations set ${readCol} = now() where id = $1`, [id]);
  res.status(204).end();
}));

// Unsend: the text disappears for both people, the bubble stays as a note.
router.delete('/messages/:id', ah(async (req, res) => {
  const id = parse(uuid, req.params.id);
  await query('update messages set deleted_at = now() where id = $1 and sender_id = $2 and deleted_at is null', [id, req.user.id]);
  res.status(204).end();
}));

router.put('/messages/:id/reaction', ah(async (req, res) => {
  const me = req.user.id;
  const id = parse(uuid, req.params.id);
  const { kind } = parse(z.object({ kind: reactionKind.nullable() }), req.body);

  const { rowCount } = await query(
    `select 1 from messages m join conversations c on c.id = m.conversation_id
      where m.id = $1 and (c.user_a = $2 or c.user_b = $2)`,
    [id, me],
  );
  if (!rowCount) throw new HttpError(404, 'Message not found.');

  if (kind) {
    await query(
      `insert into message_reactions (message_id, user_id, kind) values ($1, $2, $3)
       on conflict (message_id, user_id) do update set kind = excluded.kind`,
      [id, me, kind],
    );
  } else {
    await query('delete from message_reactions where message_id = $1 and user_id = $2', [id, me]);
  }
  res.status(204).end();
}));

export default router;
