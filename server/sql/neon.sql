-- HelpHive / Neon side
-- Holds: comments (incl. the "helpful" star), comment reactions, conversations,
-- messages, message reactions and notifications. User and post ids are Supabase uuids; the API
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
    ('friend_request', 'friend_accepted', 'post_reaction', 'post_comment', 'comment_reply', 'comment_reaction', 'comment_starred',
     'mod_warn', 'mod_restrict', 'mod_unrestrict', 'mod_ban', 'mod_unban', 'mod_strike', 'mod_remove_strike',
     'mod_delete_post', 'mod_delete_comment', 'mod_email_change', 'mod_password_change', 'mod_revert', 'mod_notice')),
  constraint notifications_not_self check (user_id <> actor_id)
);
create index if not exists notifications_user_idx on notifications (user_id, created_at desc);

-- reaction/friend events fire once per actor+target, so toggling a reaction
-- on and off does not spam the owner
-- (dropped and recreated so re-running this file picks up new types)
drop index if exists notifications_once_uq;
create unique index notifications_once_uq
  on notifications (user_id, actor_id, type, coalesce(post_id::text, ''), coalesce(comment_id::text, ''))
  where type in ('friend_request', 'friend_accepted', 'post_reaction', 'comment_reaction', 'comment_starred');

-- ---------------------------------------------------------------------------
-- helpful stars (added after the first release; safe on an existing database)
--
-- The person who wrote the post can star a comment as "helpful". Each starred
-- comment is worth one star to its author. A user's star total is never stored:
-- it is counted from their starred comments, so it can never drift (delete a
-- comment or its post and the star goes with it).
-- ---------------------------------------------------------------------------
alter table comments add column if not exists is_helpful boolean not null default false;
alter table comments add column if not exists helpful_at timestamptz;

-- profile star totals and the "resolved comments" list
create index if not exists comments_helpful_user_idx on comments (user_id, helpful_at desc) where is_helpful;
-- the helpful answer preview on feed cards
create index if not exists comments_helpful_post_idx on comments (post_id, helpful_at) where is_helpful;

-- notifications created before 'comment_starred' existed keep working: the
-- constraint above is only replaced here on databases that already had the table
alter table notifications drop constraint if exists notifications_type;
alter table notifications add constraint notifications_type check (type in
  ('friend_request', 'friend_accepted', 'post_reaction', 'post_comment', 'comment_reply', 'comment_reaction', 'comment_starred',
     'mod_warn', 'mod_restrict', 'mod_unrestrict', 'mod_ban', 'mod_unban', 'mod_strike', 'mod_remove_strike',
     'mod_delete_post', 'mod_delete_comment', 'mod_email_change', 'mod_password_change', 'mod_revert', 'mod_notice'));


-- ===========================================================================
-- ADMIN / MODERATION (HelpHive Admin for Windows)
-- Safe to re-run. Nothing here changes how existing tables behave.
-- ===========================================================================

-- System notices (moderation, announcements) come from a fixed "system" actor
-- and carry the full text the person should read.
alter table notifications add column if not exists message text;
alter table notifications add column if not exists meta jsonb;

-- ---------------------------------------------------------------------------
-- admin accounts. These are NOT Supabase users; they sign in to the admin app only.
-- ---------------------------------------------------------------------------
create table if not exists admins (
  id                    uuid primary key default gen_random_uuid(),
  email                 text not null,
  display_name          text not null,
  role                  text not null default 'moderator',
  password_hash         text not null,
  disabled              boolean not null default false,
  must_change_password  boolean not null default false,
  failed_attempts       int not null default 0,
  locked_until          timestamptz,
  last_login_at         timestamptz,
  created_at            timestamptz not null default now(),
  created_by            uuid,
  constraint admins_role check (role in ('owner', 'admin', 'moderator')),
  constraint admins_name_len check (char_length(btrim(display_name)) between 1 and 60)
);
create unique index if not exists admins_email_uq on admins (lower(email));

create table if not exists admin_sessions (
  id           uuid primary key default gen_random_uuid(),
  admin_id     uuid not null references admins (id) on delete cascade,
  ip           text,
  user_agent   text,
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at   timestamptz
);
create index if not exists admin_sessions_admin_idx on admin_sessions (admin_id, created_at desc);

-- ---------------------------------------------------------------------------
-- audit log: everything an admin does. Append-only; the trigger refuses
-- UPDATE and DELETE so even a bug (or a bad admin with API access) cannot edit history.
-- ---------------------------------------------------------------------------
create table if not exists admin_logs (
  id            bigserial primary key,
  admin_id      uuid,
  admin_name    text not null default '',
  action        text not null,
  target_type   text,
  target_id     text,
  target_label  text,
  details       jsonb not null default '{}'::jsonb,
  ip            text,
  created_at    timestamptz not null default now()
);
create index if not exists admin_logs_time_idx   on admin_logs (created_at desc);
create index if not exists admin_logs_admin_idx  on admin_logs (admin_id, created_at desc);
create index if not exists admin_logs_action_idx on admin_logs (action, created_at desc);
create index if not exists admin_logs_target_idx on admin_logs (target_id, created_at desc);

create or replace function admin_logs_immutable() returns trigger language plpgsql as $$
begin
  raise exception 'admin_logs is append-only';
end $$;
drop trigger if exists admin_logs_no_update on admin_logs;
create trigger admin_logs_no_update before update or delete on admin_logs
  for each row execute function admin_logs_immutable();

-- ---------------------------------------------------------------------------
-- moderation actions: the history of what was done to each person. The Control
-- tab reads this to undo things. `snapshot` keeps removed content so it can be restored.
-- ---------------------------------------------------------------------------
create table if not exists moderation_actions (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null,
  username       text not null default '',
  admin_id       uuid,
  admin_name     text not null default '',
  type           text not null,
  reason         text not null default '',
  note           text,                         -- internal, never shown to the user
  message        text,                         -- exactly what was sent to the user
  notified       boolean not null default false,
  auto           boolean not null default false,
  meta           jsonb not null default '{}'::jsonb,
  snapshot       jsonb,
  reversible     boolean not null default true,
  parent_id      uuid references moderation_actions (id) on delete set null,
  created_at     timestamptz not null default now(),
  ended_at       timestamptz,                  -- restriction / ban lifted
  reverted_at    timestamptz,
  reverted_by    uuid,
  reverted_name  text,
  revert_reason  text,
  constraint moderation_actions_type check (type in
    ('warn', 'restrict', 'unrestrict', 'ban', 'unban', 'strike', 'remove_strike',
     'delete_post', 'delete_comment', 'email_change', 'password_change', 'account_delete'))
);
create index if not exists mod_actions_user_idx  on moderation_actions (user_id, created_at desc);
create index if not exists mod_actions_admin_idx on moderation_actions (admin_id, created_at desc);
create index if not exists mod_actions_time_idx  on moderation_actions (created_at desc);
create index if not exists mod_actions_parent_idx on moderation_actions (parent_id);

create table if not exists user_notes (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null,
  admin_id    uuid,
  admin_name  text not null default '',
  body        text not null,
  created_at  timestamptz not null default now(),
  constraint user_notes_len check (char_length(btrim(body)) between 1 and 1000)
);
create index if not exists user_notes_user_idx on user_notes (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- reports (from people) and appeals (from banned / restricted people)
-- ---------------------------------------------------------------------------
create table if not exists reports (
  id               uuid primary key default gen_random_uuid(),
  reporter_id      uuid not null,
  target_type      text not null,
  target_id        uuid not null,
  target_user_id   uuid,
  reason           text not null,
  details          text,
  status           text not null default 'open',
  handled_by       uuid,
  handled_name     text,
  resolution_note  text,
  created_at       timestamptz not null default now(),
  handled_at       timestamptz,
  constraint reports_type   check (target_type in ('post', 'comment', 'user')),
  constraint reports_status check (status in ('open', 'actioned', 'dismissed'))
);
create index if not exists reports_status_idx on reports (status, created_at desc);
create unique index if not exists reports_once_uq on reports (reporter_id, target_type, target_id) where status = 'open';

create table if not exists appeals (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null,
  username         text not null default '',
  message          text not null,
  status           text not null default 'pending',
  decided_by       uuid,
  decided_name     text,
  decision_reason  text,
  created_at       timestamptz not null default now(),
  decided_at       timestamptz,
  constraint appeals_status check (status in ('pending', 'approved', 'denied')),
  constraint appeals_len check (char_length(btrim(message)) between 5 and 1000)
);
create index if not exists appeals_status_idx on appeals (status, created_at desc);
create index if not exists appeals_user_idx   on appeals (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- settings and usage tracking for the dashboard
-- ---------------------------------------------------------------------------
create table if not exists admin_settings (
  key         text primary key,
  value       jsonb not null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid
);

create table if not exists user_presence (
  user_id        uuid primary key,
  last_seen_at   timestamptz not null default now(),
  last_login_at  timestamptz,
  login_count    int not null default 0
);
create index if not exists user_presence_seen_idx on user_presence (last_seen_at desc);

create table if not exists login_events (
  id          bigserial primary key,
  user_id     uuid not null,
  platform    text,
  created_at  timestamptz not null default now()
);
create index if not exists login_events_time_idx on login_events (created_at desc);
create index if not exists login_events_user_idx on login_events (user_id, created_at desc);

-- one row per person per hour they were active; drives active users and peak hours
create table if not exists active_hourly (
  user_id  uuid not null,
  hour     timestamptz not null,
  primary key (user_id, hour)
);
create index if not exists active_hourly_hour_idx on active_hourly (hour);
