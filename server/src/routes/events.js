import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { admin, getPost } from '../supabase.js';
import { notify } from '../notify.js';
import { ah, HttpError, parse, uuid } from '../util.js';

/**
 * Friend requests and post reactions are written straight to Supabase by the app
 * (under row level security). After each one the app pings these endpoints. The
 * server never trusts the ping: it looks at what is really in Supabase and makes
 * the notifications match, so nobody can forge a notification for something that
 * did not happen.
 */
const router = Router();

router.post('/events/friendship', ah(async (req, res) => {
  const me = req.user.id;
  const { userId: other } = parse(z.object({ userId: uuid }), req.body);
  if (other === me) throw new HttpError(400, 'Invalid user.');

  // both ids are validated uuids, so they are safe inside the filter string
  const { data, error } = await admin
    .from('friendships')
    .select('requester_id, addressee_id, status')
    .or(`and(requester_id.eq.${me},addressee_id.eq.${other}),and(requester_id.eq.${other},addressee_id.eq.${me})`)
    .maybeSingle();
  if (error) throw new HttpError(502, 'Could not check the friendship.');

  if (!data) {
    // cancelled or declined: take any pending request pings back
    await query(
      `delete from notifications where type = 'friend_request'
         and ((user_id = $1 and actor_id = $2) or (user_id = $2 and actor_id = $1))`,
      [me, other],
    );
  } else if (data.status === 'pending' && data.requester_id === me) {
    await notify({ userId: other, actorId: me, type: 'friend_request' });
  } else if (data.status === 'accepted' && data.requester_id === other) {
    // I confirmed their request
    await notify({ userId: other, actorId: me, type: 'friend_accepted' });
    await query(
      `delete from notifications where type = 'friend_request' and user_id = $1 and actor_id = $2`,
      [me, other],
    );
  }
  res.status(204).end();
}));

router.post('/events/post-reaction', ah(async (req, res) => {
  const me = req.user.id;
  const { postId } = parse(z.object({ postId: uuid }), req.body);

  const post = await getPost(postId);
  if (!post || post.author_id === me) return res.status(204).end();

  const { data, error } = await admin
    .from('post_reactions')
    .select('kind')
    .eq('post_id', postId)
    .eq('user_id', me)
    .maybeSingle();
  if (error) throw new HttpError(502, 'Could not check the reaction.');

  if (data) {
    await notify({ userId: post.author_id, actorId: me, type: 'post_reaction', postId, snippet: data.kind });
  } else {
    await query(
      `delete from notifications where type = 'post_reaction' and user_id = $1 and actor_id = $2 and post_id = $3`,
      [post.author_id, me, postId],
    );
  }
  res.status(204).end();
}));

export default router;
