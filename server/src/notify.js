import { query } from './db.js';

/**
 * Reaction / friend notifications are one-per-actor-per-target (see the partial
 * unique index in neon.sql), so toggling a reaction does not ping the owner again.
 * Comments and replies always create a new row.
 */
export async function notify({ userId, actorId, type, postId = null, commentId = null, snippet = null }) {
  if (!userId || userId === actorId) return;
  await query(
    `insert into notifications (user_id, actor_id, type, post_id, comment_id, snippet)
     values ($1, $2, $3, $4, $5, $6)
     on conflict (user_id, actor_id, type, coalesce(post_id::text, ''), coalesce(comment_id::text, ''))
       where type in ('friend_request', 'friend_accepted', 'post_reaction', 'comment_reaction')
     do update set snippet = excluded.snippet`,
    [userId, actorId, type, postId, commentId, snippet ? snippet.slice(0, 140) : null],
  );
}
