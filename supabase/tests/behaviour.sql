-- Attack and behaviour tests for supabase/schema.sql. Run by run.sh after the stub,
-- schema.sql (twice) and helpers.sql. Every check records PASS/FAIL in t.results; an
-- unexpected error stops the run (ON_ERROR_STOP).
\set VERBOSITY terse
\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned

\set P '11111111-1111-4111-8111-111111111111'
\set Q '22222222-2222-4222-8222-222222222222'
\set COL '00000000-0000-4000-8000-0000000000a1'
\set CARD '00000000-0000-4000-8000-0000000000c1'
\set ST '00000000-0000-4000-8000-000000000051'
\set N1 '1111111111111111'
\set N2 '2222222222222222'

\set as_postgres 'reset role; select t.logout();'
\set as_anon 'reset role; select t.logout(); set role anon;'
\set as_a 'reset role; select t.login($$A$$); set role authenticated;'
\set as_b 'reset role; select t.login($$B$$); set role authenticated;'
\set as_c 'reset role; select t.login($$C$$); set role authenticated;'
\set as_d 'reset role; select t.login($$D$$, true); set role authenticated;'
\set as_f 'reset role; select t.login($$F$$); set role authenticated;'

\o /dev/null

-- ====================================================================== anon (no session)
:as_anon
select t.eq('anon: pamnot_info answers {schema: 1}', public.pamnot_info(), '{"schema": 1}'::jsonb);
select t.raises('anon: boards denied', 'select * from public.boards', '42501');
select t.raises('anon: board_items denied', 'select * from public.board_items', '42501');
select t.raises('anon: board_members denied', 'select * from public.board_members', '42501');
select t.raises('anon: board_invites denied', 'select * from public.board_invites', '42501');
select t.raises('anon: profiles denied', 'select * from public.profiles', '42501');
select t.raises('anon: create_board denied', format('select public.create_board(%L)', :'P'), '42501');
select t.raises('anon: push_items denied', format('select public.push_items(%L, %L)', :'P', '[]'), '42501');
select t.raises('anon: join_board denied', 'select public.join_board($$0000000000$$)', '42501');
select t.raises('anon: server_time_ms denied', 'select public.server_time_ms()', '42501');
select t.raises('anon: delete_board denied', format('select public.delete_board(%L)', :'P'), '42501');
select t.raises('anon: private schema denied', format('select private.is_board_member(%L)', :'P'), '42501');
select t.topic('board-data:' || :'P');
select t.raises('anon: realtime broadcast denied',
  format('insert into realtime.messages (topic, extension, payload) values (%L, $$broadcast$$, $${}$$)', 'board-data:' || :'P'),
  '42501');
select t.eq('anon: realtime messages invisible', t.rows('select * from realtime.messages'), 0::bigint);

-- ====================================================================== A creates board P
:as_a
select t.set('code1', public.create_board(:'P'));
select t.ok('create_board: returns a 10-char Crockford code', t.get('code1') ~ '^[0-9A-HJKMNP-TV-Z]{10}$', t.get('code1'));
select t.eq('create_board: idempotent for the same owner', public.create_board(:'P'), t.get('code1'));
select t.eq('create_board: owner is a member with role owner',
  (select role from public.board_members where board_id = :'P' and user_id = t.uid('A')), 'owner');
select t.eq('create_board: profile created from sign-in name',
  (select display_name from public.profiles where id = t.uid('A')), 'User A');
select t.eq('get_invite: owner reads the code', public.get_invite(:'P'), t.get('code1'));
select t.eq('board_invites: owner sees the row', t.rows('select * from public.board_invites'), 1::bigint);
select t.eq('boards: new board has rev 0 and no deleted_at',
  (select rev::text || coalesce(deleted_at::text, '-') from public.boards where id = :'P'), '0-');
select t.raises('boards: no direct insert',
  format('insert into public.boards (id, owner_id) values (gen_random_uuid(), %L)', t.uid('A')), '42501');
select t.raises('boards: owner cannot write deleted_at directly',
  format('update public.boards set deleted_at = now() where id = %L', :'P'), '42501');
select t.raises('boards: owner cannot hard-delete', format('delete from public.boards where id = %L', :'P'), '42501');
select t.raises('board_items: no direct insert',
  format('insert into public.board_items (board_id, id, kind, rev, updated_by) values (%L, gen_random_uuid(), $$card$$, 1, %L)', :'P', t.uid('A')),
  '42501');
select t.raises('board_items: no direct update', 'update public.board_items set data = $${}$$', '42501');
select t.raises('board_items: no direct delete', 'delete from public.board_items', '42501');
select t.raises('upsert_items RPC is gone', format('select public.upsert_items(%L, %L)', :'P', '[]'), '42883');
select t.raises('board_invites: no direct write',
  format('update public.board_invites set code = $$AAAAAAAAAA$$ where board_id = %L', :'P'), '42501');

-- B cannot take the id
:as_b
select t.raises('create_board: someone else''s id is 23505', format('select public.create_board(%L)', :'P'), '23505');

-- ====================================================================== push_items merge
:as_a
select t.set('r', public.push_items(:'P', jsonb_build_array(
  t.row(:'P', 'meta', '{"title":"Pano","colorIndex":3}', jsonb_build_object('title', t.h(1000), 'colorIndex', t.h(1000))),
  t.row(:'COL', 'column', '{"title":"Yapılacak","order":1024}', jsonb_build_object('title', t.h(1000), 'order', t.h(1000))),
  t.row(:'CARD', 'card', '{"title":"v1","columnId":"x","order":1024}',
        jsonb_build_object('title', t.h(1001), 'columnId', t.h(1001), 'order', t.h(1001)))))::text);
select t.eq('push: status ok', t.get('r')::jsonb ->> 'status', 'ok');
select t.eq('push: one ack per row', jsonb_array_length(t.get('r')::jsonb -> 'items'), 3);
select t.eq('push: ack carries the server fh', t.get('r')::jsonb #>> '{items,2,fh,title}', t.h(1001));
select t.eq('push: nothing lost on first write', t.get('r')::jsonb #> '{items,2,lost}', '{}'::jsonb);
select t.eq('push: three new rows take revs 1..3',
  (select string_agg(rev::text, ',' order by rev) from public.board_items where board_id = :'P'), '1,2,3');
select t.eq('push: boards.rev follows', (select rev from public.boards where id = :'P'), 3::bigint);
select t.eq('push: updated_by is the caller',
  (select count(*) from public.board_items where updated_by = t.uid('A')), 3::bigint);

-- newer wins
select t.set('r', public.push_items(:'P', jsonb_build_array(
  t.row(:'CARD', 'card', '{"title":"v2"}', jsonb_build_object('title', t.h(2000)))))::text);
select t.eq('merge: newer field wins', (select data ->> 'title' from public.board_items where id = :'CARD'), 'v2');
select t.eq('merge: changed row takes the next rev', (select rev from public.board_items where id = :'CARD'), 4::bigint);
select t.eq('merge: other fields untouched', (select data ->> 'columnId' from public.board_items where id = :'CARD'), 'x');

-- older loses and the server value comes back in lost
select t.set('r', public.push_items(:'P', jsonb_build_array(
  t.row(:'CARD', 'card', '{"title":"stale"}', jsonb_build_object('title', t.h(1500)))))::text);
select t.eq('merge: older field loses', (select data ->> 'title' from public.board_items where id = :'CARD'), 'v2');
select t.eq('merge: lost returns the server value', t.get('r')::jsonb #> '{items,0,lost}', '{"title":"v2"}'::jsonb);
select t.eq('merge: ack fh is the newer server HLC', t.get('r')::jsonb #>> '{items,0,fh,title}', t.h(2000));
select t.eq('merge: a losing push takes no rev', (select rev from public.boards where id = :'P'), 4::bigint);

-- equal HLC: no change, nothing lost
select t.set('r', public.push_items(:'P', jsonb_build_array(
  t.row(:'CARD', 'card', '{"title":"v2"}', jsonb_build_object('title', t.h(2000)))))::text);
select t.eq('merge: equal HLC is a no-op', t.get('r')::jsonb #> '{items,0,lost}', '{}'::jsonb);
select t.eq('merge: equal HLC takes no rev', (select rev from public.boards where id = :'P'), 4::bigint);

-- node breaks ties between equal ms and counter
select t.set('r', public.push_items(:'P', jsonb_build_array(
  t.row(:'CARD', 'card', '{"title":"node2"}', jsonb_build_object('title', t.h(2000, 0, :'N2')))))::text);
select t.eq('merge: higher node wins a tie', (select data ->> 'title' from public.board_items where id = :'CARD'), 'node2');

-- per-field: one field newer, one older
select t.set('r', public.push_items(:'P', jsonb_build_array(
  t.row(:'CARD', 'card', '{"title":"old","notes":"hello"}',
        jsonb_build_object('title', t.h(1200), 'notes', t.h(3000)))))::text);
select t.eq('merge: per field, the newer field lands',
  (select data ->> 'notes' from public.board_items where id = :'CARD'), 'hello');
select t.eq('merge: per field, the older field is kept',
  (select data ->> 'title' from public.board_items where id = :'CARD'), 'node2');
select t.eq('merge: per field, lost holds only the losing field',
  t.get('r')::jsonb #> '{items,0,lost}', '{"title":"node2"}'::jsonb);
select t.eq('merge: per field, one rev for the row', (select rev from public.boards where id = :'P'), 6::bigint);

-- explicit null values
select t.set('r', public.push_items(:'P', jsonb_build_array(
  t.row(:'CARD', 'card', '{"due":null}', jsonb_build_object('due', t.h(3001)))))::text);
select t.ok('merge: a null value is stored as JSON null',
  (select data ? 'due' and data -> 'due' = 'null'::jsonb from public.board_items where id = :'CARD'));

-- duplicate ids in one batch
select t.set('r', public.push_items(:'P', jsonb_build_array(
  t.row(:'CARD', 'card', '{"title":"d1"}', jsonb_build_object('title', t.h(4000))),
  t.row(:'CARD', 'card', '{"title":"d2"}', jsonb_build_object('title', t.h(4001)))))::text);
select t.eq('duplicates: later HLC wins', (select data ->> 'title' from public.board_items where id = :'CARD'), 'd2');
select t.eq('duplicates: the row takes one rev per call', (select rev from public.boards where id = :'P'), 8::bigint);
select t.set('r', public.push_items(:'P', jsonb_build_array(
  t.row(:'CARD', 'card', '{"title":"e1"}', jsonb_build_object('title', t.h(5001))),
  t.row(:'CARD', 'card', '{"title":"e0"}', jsonb_build_object('title', t.h(5000)))))::text);
select t.eq('duplicates: earlier HLC second in the batch loses',
  (select data ->> 'title' from public.board_items where id = :'CARD'), 'e1');
select t.eq('duplicates: the losing duplicate gets lost back', t.get('r')::jsonb #> '{items,1,lost}', '{"title":"e1"}'::jsonb);

-- invalid rows are skipped with status invalid; valid rows in the same batch still land
select t.set('r', public.push_items(:'P', jsonb_build_array(
  t.row('not-a-uuid', 'card', '{"title":"x"}', jsonb_build_object('title', t.h(6000))),
  t.row(gen_random_uuid()::text, 'card', '{"title":"x"}', jsonb_build_object('title', '000000000006000-00000-ABCDEF0123456789')),
  t.row(gen_random_uuid()::text, 'card', '{"title":"x"}', jsonb_build_object('title', '6000')),
  t.row(gen_random_uuid()::text, 'card', '{"title":"x"}', jsonb_build_object('title', 6000)),
  t.row(gen_random_uuid()::text, 'card', '{"title":"x"}',
        jsonb_build_object('title', t.h((extract(epoch from now()) * 1000)::bigint + 2 * 86400000))),
  t.row(gen_random_uuid()::text, 'card', '{}', jsonb_build_object('title', t.h(6000))),
  t.row(gen_random_uuid()::text, 'frame', '{"title":"x"}', jsonb_build_object('title', t.h(6000))),
  t.row(gen_random_uuid()::text, null, '{"title":"x"}', jsonb_build_object('title', t.h(6000))),
  t.row(:'COL', 'card', '{"title":"x"}', jsonb_build_object('title', t.h(6000))),
  t.row(gen_random_uuid()::text, 'meta', '{"title":"x"}', jsonb_build_object('title', t.h(6000))),
  t.row(:'P', 'card', '{"title":"x"}', jsonb_build_object('title', t.h(6000))),
  t.row(gen_random_uuid()::text, 'card', '{"title":"x"}', '{}'),
  t.row(gen_random_uuid()::text, 'card', '"str"', jsonb_build_object('title', t.h(6000))),
  t.row(gen_random_uuid()::text, 'sticky', jsonb_build_object('text', repeat('x', 270000)), jsonb_build_object('text', t.h(6000))),
  t.row(:'ST', 'sticky', '{"text":"ok","x":1}', jsonb_build_object('text', t.h(6000), 'x', t.h(6000)))))::text);
select t.eq('invalid: 14 rows skipped as invalid',
  (select count(*) from jsonb_array_elements(t.get('r')::jsonb -> 'items') e where e ->> 'status' = 'invalid'), 14::bigint);
select t.eq('invalid: the raw id is echoed', t.get('r')::jsonb #>> '{items,0,id}', 'not-a-uuid');
select t.eq('invalid: the valid row in the batch lands', (select data ->> 'text' from public.board_items where id = :'ST'), 'ok');
select t.eq('invalid: only the valid row takes a rev', (select rev from public.boards where id = :'P'), 10::bigint);
select t.eq('invalid: kind of an existing row cannot change', (select kind from public.board_items where id = :'COL'), 'column');
select t.raises('push: p_items must be an array', format('select public.push_items(%L, %L)', :'P', '{}'), '22023');
select t.raises('push: at most 200 rows',
  format('select public.push_items(%L, %L)', :'P',
         (select jsonb_agg(t.row(gen_random_uuid()::text, 'sticky', '{"x":1}', jsonb_build_object('x', t.h(7000))))
            from generate_series(1, 201))),
  '22023');
select t.eq('push: 200 rows are accepted',
  (public.push_items(:'P', (select jsonb_agg(t.row(gen_random_uuid()::text, 'sticky', '{"x":1}', jsonb_build_object('x', t.h(7000))))
                              from generate_series(1, 200)))) ->> 'status', 'ok');
select t.eq('push: 200 new rows take 200 revs', (select rev from public.boards where id = :'P'), 210::bigint);
select t.ok('rev: gap-free and unique so far', t.revs_gap_free(:'P'));

-- a signed-in role without a user id gets nothing
:as_postgres
reset role; select set_config('request.jwt.claims', '{"role":"authenticated"}', false); set role authenticated;
select t.eq('no user id: push_items is forbidden', public.push_items(:'P', '[]') ->> 'status', 'forbidden');
select t.raises('no user id: create_board refused', format('select public.create_board(%L)', gen_random_uuid()), '42501');
select t.raises('no user id: join_board refused', 'select public.join_board($$ZZZZZZZZZZ$$)', '42501');
select t.eq('no user id: sees no boards', t.rows('select * from public.boards'), 0::bigint);

-- ====================================================================== C: not a member
:as_c
select t.eq('non-member: boards hidden', t.rows('select * from public.boards'), 0::bigint);
select t.eq('non-member: items hidden', t.rows('select * from public.board_items'), 0::bigint);
select t.eq('non-member: members hidden', t.rows('select * from public.board_members'), 0::bigint);
select t.eq('non-member: invites hidden', t.rows('select * from public.board_invites'), 0::bigint);
select t.eq('non-member: profiles of others hidden', t.rows('select * from public.profiles'), 0::bigint);
select t.eq('non-member: push_items is forbidden',
  public.push_items(:'P', jsonb_build_array(t.row(:'CARD', 'card', '{"title":"hijack"}', jsonb_build_object('title', t.h(9000000)))))::text,
  '{"status": "forbidden"}');
select t.eq('non-member: push to a missing board is forbidden',
  public.push_items(gen_random_uuid(), '[]')::text, '{"status": "forbidden"}');
select t.raises('non-member: get_invite denied', format('select public.get_invite(%L)', :'P'), '42501');
select t.raises('non-member: rotate_invite denied', format('select public.rotate_invite(%L)', :'P'), '42501');
select t.raises('non-member: remove_member denied', format('select public.remove_member(%L, %L)', :'P', t.uid('A')), '42501');
select t.raises('non-member: delete_board denied', format('select public.delete_board(%L)', :'P'), '42501');
select public.leave_board(:'P');
select t.ok('non-member: topic board-data denied', not private.can_use_board_topic('board-data:' || :'P'));
select t.ok('non-member: topic board-live denied', not private.can_use_board_topic('board-live:' || :'P'));
select t.ok('topic: malformed uuid is false, not an error', not private.can_use_board_topic('board-data:not-a-uuid'));
select t.ok('topic: other prefixes are false', not private.can_use_board_topic('board:' || :'P'));
select t.topic('board-live:' || :'P');
select t.raises('non-member: realtime broadcast denied',
  format('insert into realtime.messages (topic, extension, payload) values (%L, $$broadcast$$, $${}$$)', 'board-live:' || :'P'),
  '42501');
select t.raises('non-member: realtime presence denied',
  format('insert into realtime.messages (topic, extension, payload) values (%L, $$presence$$, $${}$$)', 'board-live:' || :'P'),
  '42501');
:as_postgres
insert into realtime.messages (topic, extension, payload) values ('board-live:' || :'P', 'broadcast', '{"seed":1}');
insert into realtime.messages (topic, extension, payload) values ('board-live:' || :'P', 'postgres_changes', '{"seed":2}');
:as_c
select t.topic('board-live:' || :'P');
select t.eq('non-member: realtime messages of the topic invisible', t.rows('select * from realtime.messages'), 0::bigint);
:as_postgres
select t.eq('non-member: nothing written by the hijack', (select data ->> 'title' from public.board_items where id = :'CARD'), 'e1');

-- ====================================================================== join and rate limit
:as_c
select t.eq('join: wrong code returns null', public.join_board('ZZZZZZZZZZ'), null::jsonb);
select public.join_board('ZZZZZZZZZZ') from generate_series(1, 9);
select t.raises('join: the 11th wrong code in 15 min is rate_limited',
  'select public.join_board($$ZZZZZZZZZZ$$)', 'P0001', 'rate_limited');
select t.raises('join: even the right code waits while limited',
  format('select public.join_board(%L)', t.get('code1')), 'P0001', 'rate_limited');
:as_postgres
select t.eq('join: exactly 10 attempts recorded', (select count(*) from private.join_attempts where user_id = t.uid('C')), 10::bigint);
update private.join_attempts set attempted_at = now() - interval '20 minutes' where user_id = t.uid('C');
:as_c
select t.eq('join: the 15-minute window passes', public.join_board('ZZZZZZZZZZ'), null::jsonb);
:as_postgres
insert into private.join_attempts (user_id, attempted_at)
select t.uid('C'), now() - interval '2 hours' from generate_series(1, 39);
:as_c
select t.raises('join: 50 wrong codes a day is rate_limited', 'select public.join_board($$ZZZZZZZZZZ$$)', 'P0001', 'rate_limited');
:as_postgres
update private.join_attempts set attempted_at = now() - interval '25 hours' where user_id = t.uid('C');
:as_c
select t.eq('join: a day later the old attempts are gone', public.join_board('ZZZZZZZZZZ'), null::jsonb);
:as_postgres
select t.eq('join: attempts older than a day are purged', (select count(*) from private.join_attempts where user_id = t.uid('C')), 1::bigint);
delete from private.join_attempts;

:as_b
select t.set('j', public.join_board(lower(substr(t.get('code1'), 1, 5)) || ' - ' || lower(substr(t.get('code1'), 6)))::text);
select t.eq('join: lower case and dashes are normalised, returns board id', t.get('j')::jsonb ->> 'board_id', :'P');
select t.eq('join: title comes from the meta item', t.get('j')::jsonb ->> 'title', 'Pano');
select t.eq('join: joining twice is harmless', public.join_board(t.get('code1')) ->> 'board_id', :'P');
select t.eq('join: B is an editor', (select role from public.board_members where board_id = :'P' and user_id = t.uid('B')), 'editor');
select t.eq('member: sees the board row', t.rows('select * from public.boards'), 1::bigint);
select t.eq('member: sees the items', t.rows('select * from public.board_items'), 204::bigint);
select t.eq('member: sees both members', t.rows('select * from public.board_members'), 2::bigint);
select t.eq('member: sees co-member profiles (A and self)',
  (select string_agg(display_name, ',' order by display_name) from public.profiles), 'User A,User B');
select t.eq('member: invites stay owner-only', t.rows('select * from public.board_invites'), 0::bigint);
select t.raises('member: get_invite denied', format('select public.get_invite(%L)', :'P'), '42501');
select t.ok('member: topic board-data allowed', private.can_use_board_topic('board-data:' || :'P'));
select t.ok('member: topic board-live allowed', private.can_use_board_topic('board-live:' || :'P'));
select t.ok('member: topic prefix is case-sensitive', not private.can_use_board_topic('BOARD-LIVE:' || :'P'));
select t.topic('board-live:' || :'P');
select t.eq('member: realtime broadcast allowed',
  t.rows(format('insert into realtime.messages (topic, extension, payload) values (%L, $$broadcast$$, $${}$$)', 'board-live:' || :'P')), 1::bigint);
select t.eq('member: realtime presence allowed',
  t.rows(format('insert into realtime.messages (topic, extension, payload) values (%L, $$presence$$, $${}$$)', 'board-live:' || :'P')), 1::bigint);
select t.raises('member: other extensions cannot be sent',
  format('insert into realtime.messages (topic, extension, payload) values (%L, $$postgres_changes$$, $${}$$)', 'board-live:' || :'P'),
  '42501');
select t.eq('member: reads the topic''s messages, any extension', t.rows('select * from realtime.messages'), 4::bigint);
select t.topic('board-data:' || :'Q');
select t.raises('member: cannot send to another board''s topic',
  format('insert into realtime.messages (topic, extension, payload) values (%L, $$broadcast$$, $${}$$)', 'board-data:' || :'Q'),
  '42501');

-- escalation attempts by the editor
select t.raises('editor: cannot change owner_id', format('update public.boards set owner_id = %L', t.uid('B')), '42501');
select t.raises('editor: cannot change roles', 'update public.board_members set role = $$owner$$', '42501');
select t.raises('editor: cannot add members',
  format('insert into public.board_members (board_id, user_id, role) values (%L, %L, $$editor$$)', :'P', t.uid('C')), '42501');
select t.eq('editor: cannot delete the owner''s membership',
  t.rows(format('delete from public.board_members where board_id = %L and user_id = %L', :'P', t.uid('A'))), 0::bigint);
select t.raises('editor: cannot delete the board row', 'delete from public.boards', '42501');
select t.raises('editor: remove_member denied', format('select public.remove_member(%L, %L)', :'P', t.uid('A')), '42501');
select t.raises('editor: rotate_invite denied', format('select public.rotate_invite(%L)', :'P'), '42501');
select t.raises('editor: delete_board denied', format('select public.delete_board(%L)', :'P'), '42501');
select t.raises('editor: create_board on the shared id is 23505', format('select public.create_board(%L)', :'P'), '23505');
select t.eq('editor: push_items works',
  public.push_items(:'P', jsonb_build_array(t.row(:'CARD', 'card', '{"title":"by B"}', jsonb_build_object('title', t.h(8000, 0, :'N2'))))) ->> 'status', 'ok');
select t.eq('editor: updated_by is B, not spoofable',
  (select updated_by from public.board_items where id = :'CARD'), t.uid('B'));
select t.eq('editor: updated_at is the server clock',
  (select updated_at > now() - interval '1 minute' from public.board_items where id = :'CARD'), true);
select t.eq('profiles: upsert own profile the PostgREST way',
  t.rows(format('insert into public.profiles (id, display_name, color_index) values (%L, $$Bora$$, 4) ' ||
                'on conflict (id) do update set id = excluded.id, display_name = excluded.display_name, color_index = excluded.color_index',
                t.uid('B'))), 1::bigint);
select t.eq('profiles: own row updated', (select display_name || color_index from public.profiles where id = t.uid('B')), 'Bora4');
select t.raises('profiles: cannot create someone else''s',
  format('insert into public.profiles (id, display_name) values (%L, $$spoof$$)', t.uid('C')), '42501');
select t.eq('profiles: cannot rename someone else',
  t.rows(format('update public.profiles set display_name = $$spoof$$ where id = %L', t.uid('A'))), 0::bigint);
select t.raises('profiles: colour range is checked', format('update public.profiles set color_index = 99 where id = %L', t.uid('B')), '23514');

-- ====================================================================== removal and rotation
:as_a
select t.eq('owner: sees the new member''s profile',
  (select display_name from public.profiles where id = t.uid('B')), 'Bora');
select t.set('code2', public.remove_member(:'P', t.uid('B')));
select t.ok('remove_member: rotates the code', t.get('code2') <> t.get('code1') and t.get('code2') ~ '^[0-9A-HJKMNP-TV-Z]{10}$');
select t.eq('remove_member: new code is the invite', public.get_invite(:'P'), t.get('code2'));
select t.raises('remove_member: the owner cannot remove self', format('select public.remove_member(%L, %L)', :'P', t.uid('A')), '22023');
select t.raises('leave_board: the owner cannot leave', format('select public.leave_board(%L)', :'P'), '42501');
select t.eq('owner: no longer sees B''s profile', t.rows(format('select * from public.profiles where id = %L', t.uid('B'))), 0::bigint);
:as_b
select t.eq('removed: board row gone (status reads as revoked)', t.rows(format('select owner_id, deleted_at from public.boards where id = %L', :'P')), 0::bigint);
select t.eq('removed: items gone', t.rows('select * from public.board_items'), 0::bigint);
select t.eq('removed: push_items is forbidden',
  public.push_items(:'P', jsonb_build_array(t.row(:'CARD', 'card', '{"title":"after"}', jsonb_build_object('title', t.h(9000))))) ->> 'status', 'forbidden');
select t.ok('removed: topics denied', not private.can_use_board_topic('board-data:' || :'P') and not private.can_use_board_topic('board-live:' || :'P'));
select t.eq('removed: the old code is dead', public.join_board(t.get('code1')), null::jsonb);
select t.eq('removed: can rejoin only with the new code', public.join_board(t.get('code2')) ->> 'board_id', :'P');
select public.leave_board(:'P');
select t.eq('leave_board: the member is gone', (select count(*) from public.board_members where user_id = t.uid('B')), 0::bigint);
select public.leave_board(:'P');
select t.ok('leave_board: leaving twice is a no-op', true);
:as_a
select t.set('code3', public.rotate_invite(:'P'));
select t.ok('rotate_invite: a new code', t.get('code3') not in (t.get('code1'), t.get('code2')));
:as_b
select t.eq('rotate_invite: the previous code is dead', public.join_board(t.get('code2')), null::jsonb);
select t.eq('members may leave by deleting their own row too', public.join_board(t.get('code3')) ->> 'board_id', :'P');
select t.eq('own membership row deletable',
  t.rows(format('delete from public.board_members where board_id = %L and user_id = %L', :'P', t.uid('B'))), 1::bigint);

-- ====================================================================== anonymous users
:as_d
select t.set('codeQ', public.create_board(:'Q'));
select t.ok('anonymous: may create a board', t.get('codeQ') ~ '^[0-9A-HJKMNP-TV-Z]{10}$');
select t.eq('anonymous: may push',
  public.push_items(:'Q', jsonb_build_array(t.row(:'Q', 'meta', '{"title":"Q board"}', jsonb_build_object('title', t.h(1000))))) ->> 'status', 'ok');
select t.ok('anonymous: may read the server clock', abs(public.server_time_ms() - (extract(epoch from clock_timestamp()) * 1000)::bigint) < 5000);
:as_f
select t.eq('anonymous board: another user joins', public.join_board(t.get('codeQ')) ->> 'title', 'Q board');
:as_postgres
reset role; select set_config('request.jwt.claims', jsonb_build_object('sub', t.uid('E'), 'role', 'authenticated', 'is_anonymous', true)::text, false); set role authenticated;
select t.eq('anonymous: may join (no display name in metadata)', public.join_board(t.get('codeQ')) ->> 'board_id', :'Q');
select t.eq('anonymous: profile row made with an empty name', (select display_name from public.profiles where id = t.uid('E')), '');
:as_postgres
select t.eq('join: successful joins record no attempt',
  (select count(*) from private.join_attempts where user_id in (t.uid('E'), t.uid('F'))), 0::bigint);

-- ====================================================================== delete for everyone
:as_f
select t.raises('member: cannot delete for everyone', format('select public.delete_board(%L)', :'Q'), '42501');
:as_d
select public.delete_board(:'Q');
select t.set('del1', (select deleted_at::text from public.boards where id = :'Q'));
select t.ok('delete_board: sets deleted_at', t.get('del1') is not null);
select public.delete_board(:'Q');
select t.eq('delete_board: absorbing, deleted_at never moves', (select deleted_at::text from public.boards where id = :'Q'), t.get('del1'));
select t.eq('delete_board: push answers board_deleted',
  public.push_items(:'Q', jsonb_build_array(t.row(:'Q', 'meta', '{"title":"again"}', jsonb_build_object('title', t.h(2000))))) ->> 'status', 'board_deleted');
select t.eq('delete_board: nothing written after delete', (select data ->> 'title' from public.board_items where id = :'Q'), 'Q board');
select t.raises('delete_board: re-creating the id is 23505', format('select public.create_board(%L)', :'Q'), '23505');
select t.raises('delete_board: invite no longer readable', format('select public.get_invite(%L)', :'Q'), '42501');
select t.raises('delete_board: no new code for a deleted board', format('select public.rotate_invite(%L)', :'Q'), '42501');
:as_f
select t.eq('delete_board: members still see deleted_at', t.rows(format('select * from public.boards where id = %L and deleted_at is not null', :'Q')), 1::bigint);
select t.eq('delete_board: push from a member answers board_deleted',
  public.push_items(:'Q', '[]') ->> 'status', 'board_deleted');
:as_c
select t.eq('delete_board: the code is dead', public.join_board(t.get('codeQ')), null::jsonb);

-- ====================================================================== structure
:as_postgres
select t.ok('publication: board_items published',
  exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'board_items'));
select t.ok('publication: boards, members, invites, profiles not published',
  not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
               and tablename in ('boards', 'board_members', 'board_invites', 'profiles')));
select t.eq('replica identity: default', (select relreplident::text from pg_class where oid = 'public.board_items'::regclass), 'd');
select t.ok('RLS on every table',
  (select bool_and(relrowsecurity) from pg_class
    where oid in ('public.profiles'::regclass, 'public.boards'::regclass, 'public.board_members'::regclass,
                  'public.board_invites'::regclass, 'public.board_items'::regclass, 'private.join_attempts'::regclass)));
select t.ok('grants: clients cannot write board_items or boards',
  not has_table_privilege('authenticated', 'public.board_items', 'INSERT')
  and not has_table_privilege('authenticated', 'public.board_items', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.board_items', 'DELETE')
  and not has_table_privilege('authenticated', 'public.boards', 'INSERT')
  and not has_table_privilege('authenticated', 'public.boards', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.boards', 'DELETE'));
select t.ok('grants: anon has no table privileges',
  not exists (select 1 from information_schema.role_table_grants
               where grantee = 'anon' and table_schema in ('public', 'private')));
select t.ok('grants: anon may execute only pamnot_info',
  (select array_agg(p.proname::text order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private') and has_function_privilege('anon', p.oid, 'EXECUTE')) = array['pamnot_info']);
select t.ok('definer functions pin search_path',
  not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname in ('public', 'private') and p.prosecdef
                 and not coalesce(p.proconfig @> array['search_path=""'], false)));
select t.ok('boards has no title/columns/hlc columns',
  not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'boards'
               and column_name in ('title', 'columns', 'hlc', 'deleted', 'invite_code')));
select t.ok('rev: gap-free and unique at the end', t.revs_gap_free(:'P'));

\o
