-- Test helpers for behaviour.sql. Run as postgres after the stub and schema.sql.
drop schema if exists t cascade;
create schema t;
grant usage on schema t to anon, authenticated;

create table t.results (seq bigserial primary key, name text not null, pass boolean not null, detail text);
create table t.vars (k text primary key, v text);
-- Every item row version push_items writes, to check that revs are gap-free.
create table t.revlog (seq bigserial primary key, board_id uuid, id uuid, rev bigint, op text);

create function t.ok(p_name text, p_pass boolean, p_detail text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into t.results (name, pass, detail) values (p_name, coalesce(p_pass, false), p_detail);
end $$;

create function t.eq(p_name text, p_got anyelement, p_want anyelement) returns void
language sql security definer set search_path = '' as $$
  select t.ok(p_name, p_got is not distinct from p_want,
              'got ' || coalesce(p_got::text, 'NULL') || ', want ' || coalesce(p_want::text, 'NULL'));
$$;

-- Runs p_sql as the current role and expects SQLSTATE p_state (and hint p_hint).
create function t.raises(p_name text, p_sql text, p_state text, p_hint text default null) returns void
language plpgsql set search_path = '' as $$
declare v_state text; v_msg text; v_hint text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text, v_hint = pg_exception_hint;
  end;
  perform t.ok(p_name, v_state = p_state and (p_hint is null or v_hint = p_hint),
               coalesce(v_state || ': ' || v_msg || coalesce(' (hint ' || nullif(v_hint, '') || ')', ''),
                        'no error'));
end $$;

-- Runs p_sql as the current role and returns the number of rows it touched or returned.
create function t.rows(p_sql text) returns bigint
language plpgsql set search_path = '' as $$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end $$;

create function t.set(p_k text, p_v text) returns void
language sql security definer set search_path = '' as $$
  insert into t.vars (k, v) values (p_k, p_v) on conflict (k) do update set v = excluded.v;
$$;

create function t.get(p_k text) returns text
language sql stable security definer set search_path = '' as $$
  select v from t.vars where k = p_k;
$$;

create function t.uid(p_who text) returns uuid
language sql immutable set search_path = '' as $$
  select (repeat(lower(p_who), 8) || '-0000-4000-8000-00000000000' || lower(p_who))::uuid;
$$;

-- Pretends to be a signed-in user, the way PostgREST sets claims from the JWT.
create function t.login(p_who text, p_anonymous boolean default false) returns void
language sql set search_path = '' as $$
  select set_config('request.jwt.claims', jsonb_build_object(
    'sub', t.uid(p_who), 'role', 'authenticated', 'is_anonymous', p_anonymous,
    'user_metadata', jsonb_build_object('display_name', 'User ' || upper(p_who)))::text, false);
$$;

create function t.logout() returns void
language sql set search_path = '' as $$
  select set_config('request.jwt.claims', '{"role":"anon"}', false);
$$;

create function t.h(p_ms bigint, p_c int default 0, p_node text default '1111111111111111') returns text
language sql immutable set search_path = '' as $$
  select lpad(p_ms::text, 15, '0') || '-' || lpad(p_c::text, 5, '0') || '-' || p_node;
$$;

-- One push row: {id, kind, data, fh}.
create function t.row(p_id text, p_kind text, p_data jsonb, p_fh jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object('id', p_id, 'kind', p_kind, 'data', p_data, 'fh', p_fh);
$$;

create function t.topic(p_topic text) returns void
language sql set search_path = '' as $$
  select set_config('realtime.topic', p_topic, false);
$$;

-- Revs handed out for a board are exactly 1..boards.rev, each once.
create function t.revs_gap_free(p_board uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  with r as (select distinct rev from t.revlog where board_id = p_board),
       b as (select rev from public.boards where id = p_board)
  select (select count(*) from r) = (select rev from b)
     and (select coalesce(min(rev), 1) from r) = 1
     and (select coalesce(max(rev), 0) from r) = (select rev from b)
     -- a row repeated in one call reuses its rev; across rows a rev is never shared
     and not exists (select 1 from t.revlog l group by l.board_id, l.rev
                      having l.board_id = p_board and count(distinct l.id) > 1);
$$;

create function t.log_rev() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into t.revlog (board_id, id, rev, op) values (new.board_id, new.id, new.rev, tg_op);
  return new;
end $$;
create trigger t_log_rev after insert or update on public.board_items
  for each row execute function t.log_rev();

create function t.report() returns setof text
language sql stable security definer set search_path = '' as $$
  select (case when pass then 'PASS  ' else 'FAIL  ' end) || name ||
         (case when pass then '' else '  -- ' || coalesce(detail, '') end)
    from t.results order by seq;
$$;

grant execute on all functions in schema t to anon, authenticated;
grant select on t.results, t.vars to anon, authenticated;

insert into auth.users (id, email, is_anonymous)
select t.uid(w), lower(w) || '@example.test', w = 'D'
  from unnest(array['A', 'B', 'C', 'D', 'E', 'F']) as w;
