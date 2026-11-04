-- Pamnot · Panolar (shared boards) — server schema, version 1.
--
-- Supabase › SQL Editor › New query: paste all of this and press Run.
-- Running it again is safe; it only brings things up to date.
-- (Türkçe: Bu metnin tamamını SQL Editor’e yapıştırıp Run’a basman yeterli.
-- Tekrar çalıştırmak zararsızdır.)
--
-- Shape (docs/boards/DESIGN.md §5–6):
--  * boards          ACL and status only; nobody writes it except the RPCs below.
--  * board_members   who may read and write a board.
--  * board_invites   one 10-character code per board; only the owner reads it.
--  * board_items     every piece of board content, with per-field values (data) and
--                    per-field HLCs (fh); written only by push_items().
--  * profiles        display name and colour; visible to yourself and co-members.
-- Helpers live in schema `private`, which PostgREST does not expose.

create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

-- Older drafts had a client-side upsert and a wider create_board; they must not linger.
drop function if exists public.upsert_items(uuid, jsonb);
drop function if exists public.create_board(uuid, text, jsonb, text);

-- ------------------------------------------------------------------ tables

create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 60),
  color_index  smallint not null default 0 check (color_index between 0 and 31)
);

create table if not exists public.boards (
  id         uuid primary key,
  owner_id   uuid not null references auth.users (id) on delete cascade,
  -- Set once by delete_board(); never cleared.
  deleted_at timestamptz,
  -- Last rev handed out for this board's items (gap-free, see push_items).
  rev        bigint not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.board_members (
  board_id  uuid not null references public.boards (id) on delete cascade,
  user_id   uuid not null references auth.users (id) on delete cascade,
  role      text not null default 'editor' check (role in ('owner', 'editor')),
  joined_at timestamptz not null default now(),
  primary key (board_id, user_id)
);
create index if not exists board_members_user_idx on public.board_members (user_id);

-- Kept apart from boards so codes never travel with board rows.
create table if not exists public.board_invites (
  board_id   uuid primary key references public.boards (id) on delete cascade,
  code       text not null unique check (code ~ '^[0-9A-HJKMNP-TV-Z]{10}$'),
  created_at timestamptz not null default now()
);

create table if not exists public.board_items (
  board_id   uuid not null references public.boards (id) on delete cascade,
  id         uuid not null,
  kind       text not null check (kind in ('meta', 'column', 'card', 'sticky', 'ink')),
  data       jsonb not null default '{}'
             check (jsonb_typeof(data) = 'object' and octet_length(data::text) <= 262144),
  fh         jsonb not null default '{}' check (jsonb_typeof(fh) = 'object'),
  rev        bigint not null,
  updated_by uuid not null,
  updated_at timestamptz not null default now(),
  primary key (board_id, id)
);
-- The catch-up cursor: rows with rev > cursor, in rev order. Each row version has its own rev.
create unique index if not exists board_items_rev_idx on public.board_items (board_id, rev);

create table if not exists private.join_attempts (
  user_id      uuid not null,
  attempted_at timestamptz not null default now()
);
create index if not exists join_attempts_user_idx on private.join_attempts (user_id, attempted_at);

-- --------------------------------------------------------- helper functions
-- SECURITY DEFINER so policies can use them without recursing into RLS. None takes a user
-- argument: they only ever answer about the caller (auth.uid()).

create or replace function private.is_board_member(p_board uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.board_members m
     where m.board_id = p_board and m.user_id = (select auth.uid()));
$$;

-- For policies: evaluated once per query (hashed subplan) instead of once per row.
create or replace function private.my_board_ids()
returns setof uuid language sql stable security definer set search_path = '' as $$
  select m.board_id from public.board_members m where m.user_id = (select auth.uid());
$$;

create or replace function private.is_board_owner(p_board uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.boards b
     where b.id = p_board and b.owner_id = (select auth.uid()) and b.deleted_at is null);
$$;

create or replace function private.shares_board_with(p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.board_members mine
      join public.board_members theirs on theirs.board_id = mine.board_id
     where mine.user_id = (select auth.uid()) and theirs.user_id = p_user);
$$;

-- Realtime topics 'board-data:<uuid>' and 'board-live:<uuid>'. The CASE keeps the uuid cast
-- behind the pattern check, so a malformed topic answers false instead of raising.
create or replace function private.can_use_board_topic(p_topic text)
returns boolean language sql stable security definer set search_path = '' as $$
  select case
    when p_topic ~ '^board-(data|live):[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      then private.is_board_member(substr(p_topic, 12)::uuid)
    else false end;
$$;

-- 10 characters of Crockford base32 = 50 bits. 256 % 32 = 0, so get_byte % 32 is unbiased.
create or replace function private.new_invite_code()
returns text language sql volatile set search_path = '' as $$
  select string_agg(substr('0123456789ABCDEFGHJKMNPQRSTVWXYZ', get_byte(r.b, i) % 32 + 1, 1), '' order by i)
    from (select extensions.gen_random_bytes(10) as b) r, generate_series(0, 9) as i;
$$;

-- What people type: any case, spaces or dashes, O for 0, I/L (and Turkish İ/ı) for 1.
create or replace function private.normalize_code(p_code text)
returns text language sql immutable set search_path = '' as $$
  select translate(
           upper(regexp_replace(translate(left(coalesce(p_code, ''), 64), 'İı', 'II'), '[^0-9A-Za-z]', '', 'g')),
           'OIL', '011');
$$;

-- Gives the board a fresh code (the old one stops working) and returns it.
create or replace function private.set_invite_code(p_board uuid)
returns text language plpgsql volatile set search_path = '' as $$
declare v_code text;
begin
  loop
    v_code := private.new_invite_code();
    begin
      insert into public.board_invites (board_id, code) values (p_board, v_code)
      on conflict (board_id) do update set code = excluded.code, created_at = now();
      return v_code;
    exception when unique_violation then
      null; -- another board drew the same code (p = 2^-50): draw again
    end;
  end loop;
end $$;

-- A profile row for the caller, named from the sign-in metadata, unless one exists.
create or replace function private.ensure_profile()
returns void language sql volatile security definer set search_path = '' as $$
  insert into public.profiles (id, display_name)
  values ((select auth.uid()),
          left(coalesce((select auth.jwt()) -> 'user_metadata' ->> 'display_name', ''), 60))
  on conflict (id) do nothing;
$$;

-- ---------------------------------------------------------------- privileges
-- Supabase grants ALL on new public tables to anon and authenticated. Take it back, then
-- grant only what the app reads. Every write goes through the RPCs below, except your own
-- profile and leaving a board.
revoke all on public.profiles, public.boards, public.board_members, public.board_invites,
              public.board_items from public, anon, authenticated;
grant select, insert (id, display_name, color_index), update (id, display_name, color_index)
  on public.profiles to authenticated;
grant select on public.boards to authenticated;
grant select, delete on public.board_members to authenticated;
grant select on public.board_invites to authenticated;
grant select on public.board_items to authenticated;
revoke all on private.join_attempts from public, anon, authenticated;

-- --------------------------------------------------------------------- RLS
alter table public.profiles       enable row level security;
alter table public.boards         enable row level security;
alter table public.board_members  enable row level security;
alter table public.board_invites  enable row level security;
alter table public.board_items    enable row level security;
alter table private.join_attempts enable row level security;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or private.shares_board_with(id));
drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles for insert to authenticated
  with check (id = (select auth.uid()));
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Members see the board row, deleted or not, so they can tell "deleted" from "removed".
drop policy if exists boards_update on public.boards;
drop policy if exists boards_delete on public.boards;
drop policy if exists boards_select on public.boards;
create policy boards_select on public.boards for select to authenticated
  using (owner_id = (select auth.uid()) or id in (select private.my_board_ids()));

drop policy if exists members_select on public.board_members;
create policy members_select on public.board_members for select to authenticated
  using (board_id in (select private.my_board_ids()));
drop policy if exists members_leave on public.board_members;
create policy members_leave on public.board_members for delete to authenticated
  using (user_id = (select auth.uid()) and role <> 'owner');

drop policy if exists invites_owner_select on public.board_invites;
create policy invites_owner_select on public.board_invites for select to authenticated
  using (private.is_board_owner(board_id));

drop policy if exists items_insert on public.board_items;
drop policy if exists items_update on public.board_items;
drop policy if exists items_select on public.board_items;
create policy items_select on public.board_items for select to authenticated
  using (board_id in (select private.my_board_ids()));

-- Realtime Authorization for the app's private channels. Members read every extension of
-- their boards' topics; they may only send broadcast and presence.
drop policy if exists pamnot_board_topic_read on realtime.messages;
create policy pamnot_board_topic_read on realtime.messages for select to authenticated
  using (private.can_use_board_topic((select realtime.topic())));
drop policy if exists pamnot_board_topic_write on realtime.messages;
create policy pamnot_board_topic_write on realtime.messages for insert to authenticated
  with check (realtime.messages.extension in ('broadcast', 'presence')
              and private.can_use_board_topic((select realtime.topic())));

-- --------------------------------------------------------------------- RPCs

-- Lets the app tell whether this SQL was run (and which version). Also open to anon.
create or replace function public.pamnot_info()
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('schema', 1);
$$;

-- Server wall clock in ms, for the HLC offset.
create or replace function public.server_time_ms()
returns bigint language sql volatile set search_path = '' as $$
  select (extract(epoch from clock_timestamp()) * 1000)::bigint;
$$;

-- Registers a device-only board with the caller as owner and returns its invite code.
-- Idempotent for the same owner (a retry after a lost response returns the same code).
-- 23505 when the id belongs to someone else or was deleted: the app then re-mints the id.
create or replace function public.create_board(p_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_uid     uuid := auth.uid();
  v_owner   uuid;
  v_deleted timestamptz;
  v_code    text;
begin
  if v_uid is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  if p_id is null then
    raise exception 'board id required' using errcode = '22023';
  end if;
  insert into public.boards (id, owner_id) values (p_id, v_uid) on conflict (id) do nothing;
  select b.owner_id, b.deleted_at into v_owner, v_deleted
    from public.boards b where b.id = p_id for update;
  if v_owner is distinct from v_uid or v_deleted is not null then
    raise exception 'board id already in use' using errcode = '23505';
  end if;
  perform private.ensure_profile();
  insert into public.board_members (board_id, user_id, role) values (p_id, v_uid, 'owner')
  on conflict (board_id, user_id) do update set role = 'owner';
  select i.code into v_code from public.board_invites i where i.board_id = p_id;
  return coalesce(v_code, private.set_invite_code(p_id));
end $$;

-- The only way to write board content. Per-field last-writer-wins on HLCs compared as
-- bytes (COLLATE "C"), so Dart's String.compareTo and Postgres agree.
--
-- p_items: [{id, kind, data: {field: value}, fh: {field: hlc}}], at most 200.
-- Returns {status: 'ok', items: [{id, fh, lost}]} where fh is the row's field HLCs after the
-- merge and lost holds the server's values for fields where the pushed HLC was older.
-- A malformed row comes back as {id, status: 'invalid'} and is skipped. 'board_deleted' and
-- 'forbidden' are answers, not exceptions.
--
-- rev: the boards row is locked for the whole call, so revs are handed out in commit order;
-- only rows that actually change take one, and a counter that rolls back with its
-- transaction leaves no gaps. A client that has applied every rev up to n in order has
-- seen every committed change up to n.
create or replace function public.push_items(p_board uuid, p_items jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid      uuid := auth.uid();
  -- An HLC more than a day ahead would freeze a field for everyone until then.
  v_max_ms   bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint + 86400000;
  v_rev0     bigint;
  v_rev      bigint;
  v_deleted  timestamptz;
  v_given    jsonb := '{}';   -- item id -> rev it took in this call
  v_out      jsonb := '[]';
  v_it       jsonb;
  v_raw      text;
  v_id       uuid;
  v_kind     text;
  v_cur      public.board_items%rowtype;
  v_found    boolean;
  v_ok       boolean;
  v_data     jsonb;
  v_fh       jsonb;
  v_lost     jsonb;
  v_k        text;
  v_ih       text;
  v_ch       text;
  v_changed  boolean;
  v_row_rev  bigint;
begin
  if v_uid is null or not private.is_board_member(p_board) then
    return jsonb_build_object('status', 'forbidden');
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) > 200 then
    raise exception 'p_items must be an array of at most 200 rows' using errcode = '22023';
  end if;

  select b.rev, b.deleted_at into v_rev0, v_deleted
    from public.boards b where b.id = p_board for update;
  if not found then
    return jsonb_build_object('status', 'forbidden');
  end if;
  if v_deleted is not null then
    return jsonb_build_object('status', 'board_deleted');
  end if;
  v_rev := v_rev0;

  for v_it in select e from jsonb_array_elements(p_items) as e loop
    v_raw := case when jsonb_typeof(v_it) = 'object' then v_it ->> 'id' end;
    v_id := case when v_raw ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 then v_raw::uuid end;
    v_ok := coalesce(v_id is not null
                     and jsonb_typeof(v_it -> 'data') = 'object'
                     and jsonb_typeof(v_it -> 'fh') = 'object'
                     and v_it -> 'fh' <> '{}'::jsonb, false);
    if v_ok then
      -- Every stamped field: a well-formed, not-too-future HLC and a value to go with it.
      -- CASE, not AND: the bigint cast must only see strings that passed the pattern.
      select coalesce(bool_and(
               case when jsonb_typeof(f.value) = 'string'
                         and f.value #>> '{}' ~ '^[0-9]{15}-[0-9]{5}-[0-9a-f]{16}$'
                    then left(f.value #>> '{}', 15)::bigint <= v_max_ms
                         and char_length(f.key) between 1 and 64
                         and (v_it -> 'data') ? f.key
                    else false end), false)
        into v_ok
        from jsonb_each(v_it -> 'fh') as f;
    end if;
    if v_ok then
      select * into v_cur from public.board_items i where i.board_id = p_board and i.id = v_id;
      v_found := found;
      v_kind := case when v_found then v_cur.kind else v_it ->> 'kind' end;
      v_ok := coalesce((v_it ->> 'kind') is not distinct from v_kind
                       and v_kind in ('meta', 'column', 'card', 'sticky', 'ink')
                       -- the meta item is the board's own row, and only it
                       and (v_kind = 'meta') = (v_id = p_board), false);
    end if;
    if not v_ok then
      v_out := v_out || jsonb_build_array(jsonb_build_object('id', v_raw, 'status', 'invalid'));
      continue;
    end if;

    v_data := case when v_found then v_cur.data else '{}'::jsonb end;
    v_fh := case when v_found then v_cur.fh else '{}'::jsonb end;
    v_lost := '{}'::jsonb;
    v_changed := false;
    for v_k, v_ih in select f.key, f.value #>> '{}' from jsonb_each(v_it -> 'fh') as f loop
      v_ch := v_fh ->> v_k;
      if v_ch is null or (v_ih collate "C") > (v_ch collate "C") then
        v_data := v_data || jsonb_build_object(v_k, v_it -> 'data' -> v_k);
        v_fh := v_fh || jsonb_build_object(v_k, v_ih);
        v_changed := true;
      elsif (v_ih collate "C") < (v_ch collate "C") then
        v_lost := v_lost || jsonb_build_object(v_k, coalesce(v_data -> v_k, 'null'::jsonb));
      end if;
    end loop;

    if v_changed and octet_length(v_data::text) > 262144 then
      v_out := v_out || jsonb_build_array(jsonb_build_object('id', v_raw, 'status', 'invalid'));
      continue;
    end if;

    if v_changed then
      -- A row repeated in one call keeps the rev it took first: one rev per row per call.
      v_row_rev := (v_given ->> v_id::text)::bigint;
      if v_row_rev is null then
        v_rev := v_rev + 1;
        v_row_rev := v_rev;
        v_given := v_given || jsonb_build_object(v_id::text, v_rev);
      end if;
      if v_found then
        update public.board_items i
           set data = v_data, fh = v_fh, rev = v_row_rev,
               updated_by = v_uid, updated_at = clock_timestamp()
         where i.board_id = p_board and i.id = v_id;
      else
        insert into public.board_items (board_id, id, kind, data, fh, rev, updated_by, updated_at)
        values (p_board, v_id, v_kind, v_data, v_fh, v_row_rev, v_uid, clock_timestamp());
      end if;
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('id', v_id, 'fh', v_fh, 'lost', v_lost));
  end loop;

  if v_rev <> v_rev0 then
    update public.boards b set rev = v_rev where b.id = p_board;
  end if;
  return jsonb_build_object('status', 'ok', 'items', v_out);
end $$;

-- Returns {board_id, title} or NULL for a wrong code. A wrong code is NOT raised: an
-- exception would roll back the attempt row and the rate limit would never trigger.
create or replace function public.join_board(p_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid    uuid := auth.uid();
  v_recent int;
  v_day    int;
  v_board  uuid;
  v_title  text;
begin
  if v_uid is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  -- One user's attempts run one at a time, so parallel calls cannot all pass the count.
  perform pg_advisory_xact_lock(hashtextextended('pamnot.join:' || v_uid::text, 0));
  delete from private.join_attempts a
   where a.user_id = v_uid and a.attempted_at < now() - interval '1 day';
  select count(*) filter (where a.attempted_at > now() - interval '15 minutes'), count(*)
    into v_recent, v_day
    from private.join_attempts a where a.user_id = v_uid;
  if v_recent >= 10 or v_day >= 50 then
    raise exception 'too many wrong codes, try again later'
      using errcode = 'P0001', hint = 'rate_limited';
  end if;
  select i.board_id into v_board
    from public.board_invites i join public.boards b on b.id = i.board_id
   where i.code = private.normalize_code(p_code) and b.deleted_at is null;
  if v_board is null then
    insert into private.join_attempts (user_id) values (v_uid);
    return null;
  end if;
  perform private.ensure_profile();
  insert into public.board_members (board_id, user_id, role) values (v_board, v_uid, 'editor')
  on conflict (board_id, user_id) do nothing;
  select it.data ->> 'title' into v_title
    from public.board_items it where it.board_id = v_board and it.id = v_board;
  return jsonb_build_object('board_id', v_board, 'title', coalesce(v_title, ''));
end $$;

-- A member leaves. The owner cannot (they delete the board instead). Leaving a board you
-- are no longer on is a no-op.
create or replace function public.leave_board(p_board uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.boards b where b.id = p_board and b.owner_id = auth.uid()) then
    raise exception 'the owner cannot leave; delete the board instead' using errcode = '42501';
  end if;
  delete from public.board_members m where m.board_id = p_board and m.user_id = auth.uid();
end $$;

-- Owner only. Rotates the code in the same transaction so the removed person cannot rejoin.
create or replace function public.remove_member(p_board uuid, p_user uuid)
returns text language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_board_owner(p_board) then
    raise exception 'only the owner can remove members' using errcode = '42501';
  end if;
  if p_user = auth.uid() then
    raise exception 'the owner cannot be removed' using errcode = '22023';
  end if;
  delete from public.board_members m where m.board_id = p_board and m.user_id = p_user;
  return private.set_invite_code(p_board);
end $$;

create or replace function public.rotate_invite(p_board uuid)
returns text language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_board_owner(p_board) then
    raise exception 'only the owner can change the invite code' using errcode = '42501';
  end if;
  return private.set_invite_code(p_board);
end $$;

create or replace function public.get_invite(p_board uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.is_board_owner(p_board) then
    raise exception 'only the owner can read the invite code' using errcode = '42501';
  end if;
  return (select i.code from public.board_invites i where i.board_id = p_board);
end $$;

-- Owner only. Deletion is absorbing: deleted_at is set once, pushes answer 'board_deleted'
-- from then on and the invite code stops working.
create or replace function public.delete_board(p_board uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.boards b where b.id = p_board and b.owner_id = auth.uid()) then
    raise exception 'only the owner can delete the board' using errcode = '42501';
  end if;
  update public.boards b set deleted_at = coalesce(b.deleted_at, clock_timestamp())
   where b.id = p_board;
  delete from public.board_invites i where i.board_id = p_board;
end $$;

-- Functions are executable by PUBLIC by default and Supabase also grants anon directly.
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.is_board_member(uuid), private.my_board_ids(),
  private.is_board_owner(uuid), private.shares_board_with(uuid),
  private.can_use_board_topic(text) to authenticated;
revoke execute on function public.pamnot_info(), public.server_time_ms(),
  public.create_board(uuid), public.push_items(uuid, jsonb), public.join_board(text),
  public.leave_board(uuid), public.remove_member(uuid, uuid), public.rotate_invite(uuid),
  public.get_invite(uuid), public.delete_board(uuid)
  from public, anon, authenticated;
grant execute on function public.server_time_ms(),
  public.create_board(uuid), public.push_items(uuid, jsonb), public.join_board(text),
  public.leave_board(uuid), public.remove_member(uuid, uuid), public.rotate_invite(uuid),
  public.get_invite(uuid), public.delete_board(uuid)
  to authenticated;
grant execute on function public.pamnot_info() to anon, authenticated;

-- ---------------------------------------------------------------- realtime
-- Only board_items is published, with the default REPLICA IDENTITY: an UPDATE carries the
-- full new row. The app listens to INSERT and UPDATE filtered by board_id, never DELETE
-- (DELETE events cannot be filtered or RLS-checked). boards, board_members and
-- board_invites stay out of the publication.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and schemaname = 'public'
                    and tablename = 'board_items') then
    alter publication supabase_realtime add table public.board_items;
  end if;
  if exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'public'
                and tablename = 'boards') then
    alter publication supabase_realtime drop table public.boards;
  end if;
end $$;
