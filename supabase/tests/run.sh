#!/usr/bin/env bash
# Runs the server schema tests on a throwaway PostgreSQL database:
#   supabase_stub.sql → schema.sql (twice, it must be re-runnable) → helpers.sql →
#   behaviour.sql → parallel checks (join rate limit, concurrent pushes, row lock).
#
# Needs psql and a server you may create databases on, e.g.
#   PGHOST=/tmp/pg PGPORT=54329 PGUSER=postgres supabase/tests/run.sh
# Exits non-zero when any check fails.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
schema="${PAMNOT_SCHEMA:-$here/../schema.sql}"
db="${PAMNOT_TEST_DB:-pamnot_schema_test}"
# NOTICEs ("already exists, skipping" on the second run) are expected noise.
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"
psql_q=(psql -X -q -v ON_ERROR_STOP=1 -d "$db")

psql -X -q -d postgres -c "drop database if exists $db" >/dev/null
# Supabase databases use a linguistic collation; the schema must not depend on it.
if ! psql -X -q -d postgres -c "create database $db template template0 locale_provider icu icu_locale 'en-US' locale 'C.UTF-8'" >/dev/null 2>&1; then
  psql -X -q -d postgres -c "create database $db template template0" >/dev/null
fi

# The stub's publication warns that wal_level is not logical; that is fine here.
PGOPTIONS="$PGOPTIONS -c client_min_messages=error" "${psql_q[@]}" -f "$here/supabase_stub.sql" >/dev/null
"${psql_q[@]}" -f "$schema" >/dev/null
"${psql_q[@]}" -f "$schema" >/dev/null
"${psql_q[@]}" -f "$here/helpers.sql" >/dev/null
"${psql_q[@]}" -f "$here/behaviour.sql" >/dev/null

# ------------------------------------------------------------- parallel: join rate limit
G='0000000a-0000-4000-8000-0000000000aa'
"${psql_q[@]}" -c "insert into auth.users (id, email, is_anonymous) values ('$G', 'g@example.test', true)" >/dev/null
claims_g="{\"sub\":\"$G\",\"role\":\"authenticated\",\"is_anonymous\":true}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# Every session connects first and then waits for the same instant, so the calls really race.
start="$(date -u -d '+3 seconds' '+%Y-%m-%d %H:%M:%S.%N+00')"
for i in $(seq 1 40); do
  ( psql -X -q -At -d "$db" -c "set role authenticated" \
      -c "select set_config('request.jwt.claims', '$claims_g', false)" \
      -c "select pg_sleep_until('$start')" \
      -c "select coalesce(public.join_board('ZZZZZZZZZZ')::text, 'null')" >"$tmp/join_$i.out" 2>&1 || true ) &
done
wait
limited=$(cat "$tmp"/join_*.out | grep -c 'too many wrong codes' || true)
nulls=$(cat "$tmp"/join_*.out | grep -cx 'null' || true)
"${psql_q[@]}" >/dev/null <<SQL
select t.eq('parallel: 40 wrong codes at once record exactly 10 attempts',
  (select count(*) from private.join_attempts where user_id = '$G'), 10::bigint);
select t.eq('parallel: exactly 10 of 40 get an answer (null)', $nulls, 10);
select t.eq('parallel: the other 30 are rate_limited', $limited, 30);
SQL

# --------------------------------------------------------- parallel: concurrent pushes
R='33333333-3333-4333-8333-333333333333'
SHARED='00000000-0000-4000-8000-0000000000ee'
"${psql_q[@]}" >/dev/null <<SQL
reset role; select t.login('A'); set role authenticated;
select t.set('codeR', public.create_board('$R'));
reset role; select t.login('B'); set role authenticated;
select public.join_board(t.get('codeR'));
SQL
start="$(date -u -d '+2 seconds' '+%Y-%m-%d %H:%M:%S.%N+00')"
for who in A B; do
  node=$([ "$who" = A ] && echo 1111111111111111 || echo 2222222222222222)
  {
    echo "reset role; select t.login('$who'); set role authenticated;"
    echo "select pg_sleep_until('$start');"
    for i in $(seq 1 100); do
      ms=$((10000 + i))
      echo "select public.push_items('$R', jsonb_build_array(" \
           "t.row(gen_random_uuid()::text, 'sticky', '{\"text\":\"$who$i\"}', jsonb_build_object('text', t.h($ms, 0, '$node')))," \
           "t.row('$SHARED', 'card', '{\"title\":\"$who$i\"}', jsonb_build_object('title', t.h($ms, 0, '$node')))));"
    done
  } >"$tmp/push_$who.sql"
done
psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f "$tmp/push_A.sql" >/dev/null &
psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f "$tmp/push_B.sql" >/dev/null &
wait
"${psql_q[@]}" >/dev/null <<SQL
select t.ok('concurrent pushes: revs are gap-free and unique', t.revs_gap_free('$R'));
select t.eq('concurrent pushes: 200 new items + the shared one',
  (select count(*) from public.board_items where board_id = '$R'), 201::bigint);
select t.eq('concurrent pushes: boards.rev = distinct revs handed out',
  (select rev from public.boards where id = '$R'), (select count(distinct rev) from t.revlog where board_id = '$R'));
select t.eq('concurrent pushes: shared field ends at the highest HLC',
  (select data ->> 'title' from public.board_items where board_id = '$R' and id = '$SHARED'), 'B100');
select t.eq('concurrent pushes: shared fh is the highest HLC',
  (select fh ->> 'title' from public.board_items where board_id = '$R' and id = '$SHARED'), t.h(10100, 0, '2222222222222222'));
SQL

# ------------------------------------------------------- parallel: the boards row lock
psql -X -q -d "$db" >/dev/null <<SQL &
reset role; select t.login('A'); set role authenticated;
begin;
select public.push_items('$R', jsonb_build_array(t.row('$SHARED', 'card', '{"title":"held"}', jsonb_build_object('title', t.h(20000)))));
select pg_sleep(1.5);
commit;
SQL
sleep 0.4
"${psql_q[@]}" >/dev/null <<SQL
reset role; select t.login('B'); set role authenticated;
set lock_timeout = '200ms';
select t.raises('lock: a second push waits for the first (lock timeout while it is held)',
  format('select public.push_items(%L, %L)', '$R',
         jsonb_build_array(t.row('$SHARED', 'card', '{"title":"waiting"}', jsonb_build_object('title', t.h(20001, 0, '2222222222222222'))))),
  '55P03');
SQL
wait
"${psql_q[@]}" >/dev/null <<SQL
reset role; select t.login('B'); set role authenticated;
select t.eq('lock: after the commit the next push takes the next rev',
  (public.push_items('$R', jsonb_build_array(t.row('$SHARED', 'card', '{"title":"after"}',
      jsonb_build_object('title', t.h(20002, 0, '2222222222222222'))))) ->> 'status'), 'ok');
reset role;
select t.ok('lock: revs still gap-free', t.revs_gap_free('$R'));
SQL

# --------------------------------------------------------------------------- report
psql -X -q -At -d "$db" -c "select * from t.report()"
total=$(psql -X -q -At -d "$db" -c "select count(*) from t.results")
failed=$(psql -X -q -At -d "$db" -c "select count(*) from t.results where not pass")
echo "----"
echo "$total checks, $failed failed"
[ "$failed" = 0 ]
