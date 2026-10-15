-- HelpHive / Supabase side
-- Holds: profiles, posts, post reactions, friendships + the media buckets.
-- Comments, messages and notifications live in Neon (see server/sql/neon.sql).
--
-- Run the whole file once in  Supabase dashboard > SQL Editor.
-- It is safe to re-run.

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  username    text not null,
  full_name   text not null default '',
  bio         text not null default '',
  location    text not null default '',
  avatar_url  text,
  cover_url   text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint profiles_username_format check (username ~ '^[a-z0-9_.]{3,24}$'),
  constraint profiles_name_len        check (char_length(full_name) <= 60),
  constraint profiles_bio_len         check (char_length(bio) <= 280),
  constraint profiles_location_len    check (char_length(location) <= 80),
  constraint profiles_avatar_https    check (avatar_url is null or (avatar_url ~ '^https://' and char_length(avatar_url) <= 500)),
  constraint profiles_cover_https     check (cover_url  is null or (cover_url  ~ '^https://' and char_length(cover_url)  <= 500))
);
create unique index if not exists profiles_username_uq on public.profiles (username);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

-- A profile row is created automatically for every new auth user
-- (email sign-up and Google both end up here).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  meta      jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  base      text;
  candidate text;
  tries     int := 0;
  pic       text := coalesce(meta->>'avatar_url', meta->>'picture');
begin
  base := lower(regexp_replace(split_part(coalesce(new.email, ''), '@', 1), '[^a-zA-Z0-9_.]', '', 'g'));
  base := left(base, 16);
  if char_length(base) < 3 then
    base := 'user' || base;
  end if;

  candidate := base;
  while exists (select 1 from public.profiles where username = candidate) and tries < 25 loop
    tries := tries + 1;
    candidate := base || '_' || substr(md5(random()::text || clock_timestamp()::text), 1, 4);
  end loop;

  insert into public.profiles (id, username, full_name, avatar_url)
  values (
    new.id,
    candidate,
    left(coalesce(meta->>'full_name', meta->>'name', ''), 60),
    case when pic ~ '^https://' and char_length(pic) <= 500 then pic end
  );
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- posts
-- ---------------------------------------------------------------------------
create table if not exists public.posts (
  id           uuid primary key default gen_random_uuid(),
  author_id    uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  body         text not null default '',
  image_path   text,
  category     text not null default 'general',
  is_resolved  boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint posts_body_len     check (char_length(body) <= 2000),
  constraint posts_category     check (category in ('general', 'request', 'offer')),
  constraint posts_not_empty    check (char_length(btrim(body)) > 0 or image_path is not null),
  -- an image can only point into the author's own folder
  constraint posts_image_owner  check (image_path is null or split_part(image_path, '/', 1) = author_id::text),
  constraint posts_image_len    check (image_path is null or char_length(image_path) <= 200)
);
create index if not exists posts_created_idx        on public.posts (created_at desc);
create index if not exists posts_author_created_idx on public.posts (author_id, created_at desc);

drop trigger if exists posts_touch on public.posts;
create trigger posts_touch before update on public.posts
  for each row execute function public.touch_updated_at();

-- crude anti-spam: 20 posts per hour per person
create or replace function public.limit_post_rate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select count(*) from public.posts
        where author_id = new.author_id and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'You are posting too fast. Try again in a bit.' using errcode = 'P0001';
  end if;
  return new;
end $$;

drop trigger if exists posts_rate on public.posts;
create trigger posts_rate before insert on public.posts
  for each row execute function public.limit_post_rate();

-- ---------------------------------------------------------------------------
-- reactions + friendships (written only through the functions further down)
-- ---------------------------------------------------------------------------
create table if not exists public.post_reactions (
  post_id     uuid not null references public.posts (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  kind        text not null,
  created_at  timestamptz not null default now(),
  primary key (post_id, user_id),
  constraint post_reactions_kind check (kind in ('like', 'love', 'haha', 'wow', 'sad'))
);
create index if not exists post_reactions_user_idx on public.post_reactions (user_id);

create table if not exists public.friendships (
  id            uuid primary key default gen_random_uuid(),
  requester_id  uuid not null references public.profiles (id) on delete cascade,
  addressee_id  uuid not null references public.profiles (id) on delete cascade,
  status        text not null default 'pending',
  created_at    timestamptz not null default now(),
  constraint friendships_status check (status in ('pending', 'accepted')),
  constraint friendships_not_self check (requester_id <> addressee_id)
);
-- one row per pair, whichever way round it was sent
create unique index if not exists friendships_pair_uq
  on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index if not exists friendships_addressee_idx on public.friendships (addressee_id, status);
create index if not exists friendships_requester_idx on public.friendships (requester_id, status);

-- ---------------------------------------------------------------------------
-- row level security + least-privilege grants
-- ---------------------------------------------------------------------------
alter table public.profiles       enable row level security;
alter table public.posts          enable row level security;
alter table public.post_reactions enable row level security;
alter table public.friendships    enable row level security;

revoke all on public.profiles, public.posts, public.post_reactions, public.friendships
  from anon, authenticated;

grant select on public.profiles, public.posts, public.post_reactions, public.friendships to authenticated;
grant update (username, full_name, bio, location, avatar_url, cover_url) on public.profiles to authenticated;
grant insert (author_id, body, image_path, category) on public.posts to authenticated;
grant update (body, image_path, category, is_resolved) on public.posts to authenticated;
-- no direct DELETE on posts: removal goes through the API server so the
-- comments in Neon and the image in storage are cleaned up together.

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated using (true);

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists posts_select on public.posts;
create policy posts_select on public.posts
  for select to authenticated using (true);

drop policy if exists posts_insert_own on public.posts;
create policy posts_insert_own on public.posts
  for insert to authenticated
  with check (author_id = (select auth.uid()));

drop policy if exists posts_update_own on public.posts;
create policy posts_update_own on public.posts
  for update to authenticated
  using (author_id = (select auth.uid()))
  with check (author_id = (select auth.uid()));

drop policy if exists reactions_select on public.post_reactions;
create policy reactions_select on public.post_reactions
  for select to authenticated using (true);

drop policy if exists friendships_select_party on public.friendships;
create policy friendships_select_party on public.friendships
  for select to authenticated
  using (requester_id = (select auth.uid()) or addressee_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- functions the app calls
-- ---------------------------------------------------------------------------

-- feed / profile wall / post search / single post, all in one place
drop function if exists public.get_feed(int, timestamptz, uuid, text, text);
create or replace function public.get_feed(
  p_limit    int         default 20,
  p_before   timestamptz default null,
  p_author   uuid        default null,
  p_search   text        default null,
  p_category text        default null,
  p_id       uuid        default null
)
returns table (
  id uuid, author_id uuid, username text, full_name text, avatar_url text,
  body text, image_path text, category text, is_resolved boolean,
  created_at timestamptz, updated_at timestamptz,
  reaction_count bigint, my_reaction text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id, p.author_id, a.username, a.full_name, a.avatar_url,
         p.body, p.image_path, p.category, p.is_resolved,
         p.created_at, p.updated_at,
         (select count(*) from public.post_reactions r where r.post_id = p.id),
         (select r.kind from public.post_reactions r
            where r.post_id = p.id and r.user_id = auth.uid())
  from public.posts p
  join public.profiles a on a.id = p.author_id
  where (p_id       is null or p.id = p_id)
    and (p_before   is null or p.created_at < p_before)
    and (p_author   is null or p.author_id = p_author)
    and (p_category is null or p.category = p_category)
    and (p_search is null or btrim(p_search) = ''
         or position(lower(btrim(p_search)) in lower(p.body)) > 0)
  order by p.created_at desc
  limit least(greatest(p_limit, 1), 50);
$$;

-- people grid, friend requests and user search
create or replace function public.get_people(
  p_filter text default 'all',      -- all | friends | requests | sent
  p_query  text default null,
  p_limit  int  default 40,
  p_offset int  default 0
)
returns table (
  id uuid, username text, full_name text, bio text, avatar_url text,
  friendship_id uuid, relation text   -- none | friends | sent | received
)
language sql
stable
security invoker
set search_path = ''
as $$
  select t.id, t.username, t.full_name, t.bio, t.avatar_url, t.friendship_id, t.relation
  from (
    select p.id, p.username, p.full_name, p.bio, p.avatar_url, p.created_at,
           f.id as friendship_id,
           case
             when f.id is null then 'none'
             when f.status = 'accepted' then 'friends'
             when f.requester_id = auth.uid() then 'sent'
             else 'received'
           end as relation
    from public.profiles p
    left join public.friendships f
      on (f.requester_id = auth.uid() and f.addressee_id = p.id)
      or (f.addressee_id = auth.uid() and f.requester_id = p.id)
    where p.id <> auth.uid()
      and (p_query is null or btrim(p_query) = ''
           or position(lower(btrim(p_query)) in lower(p.username || ' ' || p.full_name)) > 0)
  ) t
  where case p_filter
          when 'friends'  then t.relation = 'friends'
          when 'requests' then t.relation = 'received'
          when 'sent'     then t.relation = 'sent'
          else true
        end
  order by (t.relation = 'received') desc, t.created_at desc
  limit least(greatest(p_limit, 1), 100)
  offset greatest(p_offset, 0);
$$;

-- one profile with counters. security definer because friend counts need to
-- see friendships the caller is not part of; only aggregates leave the function.
create or replace function public.get_profile_card(p_id uuid)
returns table (
  id uuid, username text, full_name text, bio text, location text,
  avatar_url text, cover_url text, created_at timestamptz,
  posts_count bigint, friends_count bigint,
  friendship_id uuid, relation text
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.username, p.full_name, p.bio, p.location,
         p.avatar_url, p.cover_url, p.created_at,
         (select count(*) from public.posts x where x.author_id = p.id),
         (select count(*) from public.friendships g
            where g.status = 'accepted' and (g.requester_id = p.id or g.addressee_id = p.id)),
         f.id,
         case
           when p.id = auth.uid() then 'self'
           when f.id is null then 'none'
           when f.status = 'accepted' then 'friends'
           when f.requester_id = auth.uid() then 'sent'
           else 'received'
         end
  from public.profiles p
  left join public.friendships f
    on p.id <> auth.uid()
   and ((f.requester_id = auth.uid() and f.addressee_id = p.id)
     or (f.addressee_id = auth.uid() and f.requester_id = p.id))
  where p.id = p_id and auth.uid() is not null;
$$;

create or replace function public.set_post_reaction(p_post uuid, p_kind text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare me uuid := auth.uid();
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if p_kind is null then
    delete from public.post_reactions where post_id = p_post and user_id = me;
    return;
  end if;

  if p_kind not in ('like', 'love', 'haha', 'wow', 'sad') then
    raise exception 'unknown reaction' using errcode = '22023';
  end if;
  if not exists (select 1 from public.posts where id = p_post) then
    raise exception 'post not found' using errcode = 'P0002';
  end if;

  insert into public.post_reactions (post_id, user_id, kind)
  values (p_post, me, p_kind)
  on conflict (post_id, user_id) do update set kind = excluded.kind;
end $$;

create or replace function public.send_friend_request(p_user uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me       uuid := auth.uid();
  existing public.friendships;
  fid      uuid;
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_user is null or p_user = me then
    raise exception 'invalid user' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_user) then
    raise exception 'user not found' using errcode = 'P0002';
  end if;

  select * into existing from public.friendships
   where (requester_id = me and addressee_id = p_user)
      or (requester_id = p_user and addressee_id = me);

  if found then
    -- they already asked me: treat "add" as "confirm"
    if existing.status = 'pending' and existing.addressee_id = me then
      update public.friendships set status = 'accepted' where id = existing.id;
    end if;
    return existing.id;
  end if;

  insert into public.friendships (requester_id, addressee_id)
  values (me, p_user)
  returning id into fid;
  return fid;
end $$;

-- confirm (p_accept = true) or decline (false) a request sent to me
create or replace function public.respond_friend_request(p_id uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare me uuid := auth.uid();
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if p_accept then
    update public.friendships set status = 'accepted'
     where id = p_id and addressee_id = me and status = 'pending';
  else
    delete from public.friendships
     where id = p_id and addressee_id = me and status = 'pending';
  end if;
end $$;

-- cancel my own request, or unfriend
create or replace function public.remove_friendship(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare me uuid := auth.uid();
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  delete from public.friendships
   where id = p_id and (requester_id = me or addressee_id = me);
end $$;

-- (account deletion is handled by the API server: it clears Neon rows and
-- storage files, then removes the auth user with the service role key.)

-- functions are executable by PUBLIC by default; close that and open only what the app needs
revoke execute on function
  public.get_feed(int, timestamptz, uuid, text, text, uuid),
  public.get_people(text, text, int, int),
  public.get_profile_card(uuid),
  public.set_post_reaction(uuid, text),
  public.send_friend_request(uuid),
  public.respond_friend_request(uuid, boolean),
  public.remove_friendship(uuid)
from public, anon;

grant execute on function
  public.get_feed(int, timestamptz, uuid, text, text, uuid),
  public.get_people(text, text, int, int),
  public.get_profile_card(uuid),
  public.set_post_reaction(uuid, text),
  public.send_friend_request(uuid),
  public.respond_friend_request(uuid, boolean),
  public.remove_friendship(uuid)
to authenticated;

-- ---------------------------------------------------------------------------
-- storage: three public-read buckets, writes only inside your own folder
-- (<user id>/<random name>.jpg), size and mime type capped at the bucket.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', true, 2097152, array['image/jpeg', 'image/png', 'image/webp']),
  ('covers',  'covers',  true, 4194304, array['image/jpeg', 'image/png', 'image/webp']),
  ('posts',   'posts',   true, 6291456, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists helphive_media_select on storage.objects;
create policy helphive_media_select on storage.objects
  for select to authenticated
  using (bucket_id in ('avatars', 'covers', 'posts')
         and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists helphive_media_insert on storage.objects;
create policy helphive_media_insert on storage.objects
  for insert to authenticated
  with check (bucket_id in ('avatars', 'covers', 'posts')
              and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists helphive_media_update on storage.objects;
create policy helphive_media_update on storage.objects
  for update to authenticated
  using (bucket_id in ('avatars', 'covers', 'posts')
         and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id in ('avatars', 'covers', 'posts')
              and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists helphive_media_delete on storage.objects;
create policy helphive_media_delete on storage.objects
  for delete to authenticated
  using (bucket_id in ('avatars', 'covers', 'posts')
         and (storage.foldername(name))[1] = (select auth.uid())::text);
