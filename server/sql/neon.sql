-- HelpHive / Neon side
-- Holds: comments, comment reactions, conversations, messages, message
-- reactions and notifications. User and post ids are Supabase uuids; the API
-- server checks them against Supabase before writing, so there are no foreign
-- keys across the two databases.
--
-- Run once in the Neon SQL editor (or: psql "$DATABASE_URL" -f neon.sql).
-- Safe to re-run.

-- ---------------------------------------------------------------------------
-- comments (one level of replies)
-- ---------------------------------------------------------------------------
create table if not exists comments (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null,
  parent_id   uuid references comments (id) on delete cascade,
  user_id     uuid not null,
  body        text not null,
  edited      boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint comments_body_len check (char_length(btrim(body)) between 1 and 1000)
);
create index if not exists comments_post_idx   on comments (post_id, created_at);
create index if not exists comments_parent_idx on comments (parent_id);
create index if not exists comments_user_idx   on comments (user_id);

create table if not exists comment_reactions (
  comment_id  uuid not null references comments (id) on delete cascade,
  user_id     uuid not null,
  kind        text not null,
  created_at  timestamptz not null default now(),
  primary key (comment_id, user_id),
  constraint comment_reactions_kind check (kind in ('like', 'love', 'haha', 'wow', 'sad'))
);

-- ---------------------------------------------------------------------------
-- direct messages. A pair of people shares exactly one conversation;
-- user_a is always the smaller uuid so the pair has a single canonical form.
-- ---------------------------------------------------------------------------
create table if not exists conversations (
  id               uuid primary key default gen_random_uuid(),
  user_a           uuid not null,
  user_b           uuid not null,
  a_read_at        timestamptz not null default now(),
  b_read_at        timestamptz not null default now(),
  last_message_at  timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  constraint conversations_order check (user_a < user_b),
  constraint conversations_pair  unique (user_a, user_b)
);
create index if not exists conversations_a_idx on conversations (user_a, last_message_at desc);
create index if not exists conversations_b_idx on conversations (user_b, last_message_at desc);

create table if not exists messages (
  id               uuid primary key default gen_random_uuid(),
  conversation_id  uuid not null references conversations (id) on delete cascade,
  sender_id        uuid not null,
  body             text not null,
  reply_to         uuid references messages (id) on delete set null,
  deleted_at       timestamptz,
  created_at       timestamptz not null default now(),
  constraint messages_body_len check (char_length(btrim(body)) between 1 and 2000)
);
create index if not exists messages_conv_idx on messages (conversation_id, created_at desc);

create table if not exists message_reactions (
  message_id  uuid not null references messages (id) on delete cascade,
  user_id     uuid not null,
  kind        text not null,
  created_at  timestamptz not null default now(),
  primary key (message_id, user_id),
  constraint message_reactions_kind check (kind in ('like', 'love', 'haha', 'wow', 'sad'))
);

-- ---------------------------------------------------------------------------
-- notifications (friend requests, reactions, comments, replies)
-- ---------------------------------------------------------------------------
create table if not exists notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null,            -- who receives it
  actor_id    uuid not null,            -- who did it
  type        text not null,
  post_id     uuid,
  comment_id  uuid,
  snippet     text,
  read_at     timestamptz,
  created_at  timestamptz not null default now(),
  constraint notifications_type check (type in
    ('friend_request', 'friend_accepted', 'post_reaction', 'post_comment', 'comment_reply', 'comment_reaction')),
  constraint notifications_not_self check (user_id <> actor_id)
);
create index if not exists notifications_user_idx on notifications (user_id, created_at desc);

-- reaction/friend events fire once per actor+target, so toggling a reaction
-- on and off does not spam the owner
create unique index if not exists notifications_once_uq
  on notifications (user_id, actor_id, type, coalesce(post_id::text, ''), coalesce(comment_id::text, ''))
  where type in ('friend_request', 'friend_accepted', 'post_reaction', 'comment_reaction');
