-- A minimal stand-in for the parts of a Supabase database that schema.sql touches, so the
-- schema and its tests run on a plain PostgreSQL 16. Not for production.
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role service_role nologin bypassrls; exception when duplicate_object then null; end $$;

create schema if not exists auth;
create schema if not exists extensions;
create schema if not exists realtime;
create extension if not exists pgcrypto with schema extensions;
grant usage on schema public, auth, extensions to anon, authenticated;

create table if not exists auth.users (id uuid primary key, email text, is_anonymous boolean not null default false);

-- PostgREST puts the verified JWT claims into request.jwt.claims; auth.uid() reads `sub`.
create or replace function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(auth.jwt() ->> 'sub', '')::uuid $$;
grant execute on function auth.jwt(), auth.uid() to anon, authenticated;

-- Realtime Authorization checks policies on realtime.messages with realtime.topic() set.
create table if not exists realtime.messages (
  id          bigserial primary key,
  topic       text not null,
  extension   text not null,
  payload     jsonb,
  inserted_at timestamptz default now()
);
alter table realtime.messages enable row level security;
create or replace function realtime.topic() returns text language sql stable as $$
  select nullif(current_setting('realtime.topic', true), '') $$;
grant usage on schema realtime to authenticated, anon;
grant select, insert on realtime.messages to authenticated, anon;
grant usage on all sequences in schema realtime to authenticated, anon;
grant execute on function realtime.topic() to authenticated, anon;

-- Supabase's default privileges for objects that postgres creates in public.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;

do $$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;
