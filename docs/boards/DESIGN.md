# Boards (Panolar) — design

Status: v1 design, agreed after four independent reviews (sync correctness, security, canvas
performance and input, product/UX). This document is authoritative; where an older review note
disagrees, this document wins.

## 1. What v1 is

Takip › **Panolar** holds boards. A board has two views of the same data:

- **Tuval** (canvas): an infinite, zoomable whiteboard. It shows the board's columns as one movable
  block of lanes with their cards, plus free sticky notes and pen ink (Apple Pencil, stylus, mouse,
  finger).
- **Kanban**: the columns side by side, cards dragged between and within them.

Boards are device-only until shared. Sharing uploads the board to a Supabase project the owner sets
up once; teammates join by pasting one invite text and typing a name. Edits sync in realtime and
work offline.

Item kinds in v1: `meta` (one per board, id = board id), `column`, `card`, `sticky`, `ink`.
Out of v1: connectors, generic frames, text tool, images, sticky resize, live drag broadcast,
e-mail accounts, Today/Plan integration, labels, priority, comments, follow mode, viewer role.

## 2. Data model

Every piece of board content is an **item** with per-field values and per-field HLCs.

| kind | fields (`f`) |
|---|---|
| meta | `title`, `colorIndex`, `laneX`, `laneY` (canvas origin of the lane block) |
| column | `title`, `colorIndex`, `isDone`, `order`, `deleted` |
| card | `title`, `notes`, `columnId`, `order`, `due` (`yyyy-MM-dd` or null), `subtasks` (list of `{id,title,done}`), `colorIndex`, `assigneeId`, `deleted` |
| sticky | `x`, `y`, `z`, `text`, `colorIndex`, `deleted` |
| ink | `x`, `y`, `z`, `strokes` (InkCodec string of exactly one stroke, points relative to `x`,`y`), `deleted` |

Rules:
- Card position on the canvas is **derived** from `columnId` + `order` (lane layout); cards have no
  stored x/y. Stickies and ink exist only on the canvas.
- A card whose `columnId` is missing or deleted renders in the first live column (by
  `(order, id)`). This is a render rule, never written back.
- Sort columns and cards by `(order, id)`, stickies/ink by `(z, id)`.
- Defaults (three columns) are created once at board creation. A client that sees zero columns
  never seeds them.
- Deletion is the `deleted` field (tombstone). Delete wins over concurrent edits; only an explicit
  restore (undo) brings an item back.

### Write groups (one HLC tick per group)
- card move: `{columnId, order}` (order alone for a reorder in the same column)
- sticky/ink move: `{x, y}`; bring to front / send to back: `{z}`
- delete / restore: `{deleted}`
- any text or scalar edit: that field alone
- card sheet commit: the changed fields, one tick
- lane block move: `{laneX, laneY}`

### Fractional order
`between(a, b) = a + (b - a) * (0.25 + 0.5 * rnd)`; ends use ±1024 from the neighbour; empty list
starts at 1024. Renormalise a column only when the midpoint is not strictly between its
neighbours or `b - a < 1e-9 * max(1, |a|)`: set `order = 1024 * (i + 1)` in `(order, id)` order,
writing `order` only.

## 3. HLC

Fixed-width ASCII: `MMMMMMMMMMMMMMM-CCCCC-NNNNNNNNNNNNNNNN` (15-digit ms, 5-digit counter, 16 lowercase
hex node). Plain string comparison orders it; Postgres compares with `COLLATE "C"`.
- One clock per app process. Node: `Random.secure()` per launch, never persisted, never a user id.
- `tick()`: `w = now + offsetMs`; if `w > ms` → `(w, 0)` else `c + 1`, rolling `c > 99999` into
  `ms + 1`.
- `observe(h)`: `(ms, c) = max((ms, c), parse(h))` — on every HLC in a loaded board document and on
  every received field HLC.
- `offsetMs` = server time − device time, measured on connect with `server_time_ms()`
  (`offset = s - (t0 + t1) / 2`), persisted in settings.
- Display times come from the server's `updated_at`, never from HLCs.

## 4. Local storage (KeyValueStore)

- `boards_index`: `{v:1, boards:[{id, title, colorIndex, state, updatedAt, counts…}]}` — summaries
  for the list, rewritten when a board document is saved.
- `board_<id>`: the whole board in one document, so one write is atomic:
  `{v:1, id, state: local|uploading|shared|deleted|revoked, account: {host, userId}?, cursor: int,
  items: {<itemId>: {k, f, h, d: [dirty fields]}}}`. Ink `strokes` are not in it.
- `boardink_<itemId>`: the encoded stroke, written once.
- `board_view_<id>`: this device's `{view: canvas|kanban, ox, oy, scale}`; never synced.

There is no outbox document: `d` (dirty fields) inside each item is the outbox.

## 5. Sync protocol (shared boards)

Server rows: `board_items(board_id, id, kind, data jsonb, fh jsonb, rev bigint, updated_by,
updated_at)`, primary key `(board_id, id)`. `rev` is gap-free and commit-ordered per board (assigned
under a lock on the `boards` row). The client's only catch-up cursor is the highest `rev` it has
applied in order.

**Merge** (pull rows, realtime rows and push acks): for each field `k` in the row's `fh`: observe
the HLC; if it is greater than the local `h[k]` and `data` has `k`, take the value and HLC and drop
`k` from `d`; if equal, drop `k` from `d`; if smaller, ignore. Never merge a record with
`errors != null` or missing `data`/`fh`/`rev`; request a catch-up instead. No echo filtering, no
buffering: the merge is idempotent and commutative.

**Push**: debounce 300 ms (max 2 s), single flight. Batch ≤200 rows / ~256 KB of items with
non-empty `d`, each row `{id, kind, data:{k: f[k]}, fh:{k: h[k]}}` for `k` in `d`; remember
`sent[id][k] = h[k]`. Call `push_items(p_board, p_items)`. Result `ok` → per item, per sent `k`:
if server `fh[k] == h[k]` remove from `d`; if server is newer and `lost` has `k`, apply it and remove;
else keep. `board_deleted` / `forbidden` → state `deleted` / `revoked`, clear `d`, surface in UI.
Network/5xx → backoff 1…60 s. Acks never move the cursor.

**Connect / catch-up state machine** (one per open shared board; phases offline → joining →
catchingUp → live):
1. Subscribe first: private channel `board-data:<id>`, postgres_changes INSERT and UPDATE on
   `board_items` filtered `board_id=eq.<id>` (never `all`), plus system events.
2. Run a single-flight catch-up (with a rerun flag) on: every `subscribed` status (repeats too),
   every system event with `extension == postgres_changes && status == ok`, app resume, a realtime
   row with `rev > cursor + 1` (1 s debounce), and a 60 s foreground poll.
3. Catch-up: read board status (`boards` row: missing → revoked, `deleted_at` → deleted), then page
   `board_items where board_id = ? and rev > cursor order by rev limit 500` until a short page,
   merging and advancing the cursor.
4. A realtime row advances the cursor only when `rev == cursor + 1`.
5. On `channelError` / `timedOut` / unexpected `closed`: 15 s watchdog; if not re-subscribed,
   remove the channel and recreate it with backoff (1…30 s + jitter).

Presence and cursors use a second private channel `board-live:<id>` (presence key = HLC node id,
payload `{userId, name, colorIndex, view, editing}`; `cursor {x, y}` broadcast ≤8 Hz, only while the
pointer moves ≥2 px, only from mouse/stylus hover or a drag, and only when someone else is
present). Peers are smoothed (τ = 60 ms) and fade after 10 s.

**Sharing a device-only board**: one atomic document write: state `uploading`, account set, cursor
0, local tombstones dropped, every field of every live item dirty. Call `create_board(p_id)` (returns
the invite code; idempotent for the same owner; `23505` if the id is someone else's → re-mint the
board id locally), then the normal push loop. First `ok` → `shared`.

**Joining**: `join_board(code)` returns `{board_id, title}`; create the document with state `shared`,
cursor 0, connect.

**Scoping**: a shared board document records `{host, userId}`. Sync runs only when they match the
current session; otherwise the board is hidden. Revocation (status row missing, 42501, or a channel
error mentioning Unauthorized) → read-only copy, offer "save as device-only copy".

## 6. Server (Supabase) — `supabase/schema.sql`

- Schema `private` (not exposed by PostgREST) holds helpers: `is_board_member`, `is_board_owner`,
  `shares_board_with`, `can_use_board_topic`, invite code generation/normalisation, join attempts.
  All SECURITY DEFINER functions `set search_path = ''`, take no user argument and answer only about
  `auth.uid()`.
- `boards(id, owner_id, deleted_at, rev, created_at)`: ACL and status only; members may SELECT; no
  client writes (all through RPCs). Not in the realtime publication.
- `board_members(board_id, user_id, role owner|editor)`: members see co-members; a non-owner may
  delete their own row (leave); no client insert/update.
- `board_invites(board_id, code)`: 10 Crockford base32 characters (50 bits) from
  `gen_random_bytes`; only the owner may SELECT.
- `board_items`: SELECT for members; all writes revoked from clients; written only by
  `push_items`. In the realtime publication with default replica identity.
- `profiles(id, display_name, color_index)`: visible to yourself and people who share a board with
  you; you write only your own row.
- RPCs (granted to `authenticated`, which includes anonymous users): `create_board(p_id)`,
  `push_items(p_board, p_items)` (per-field merge, rev bump, per-row `{id, fh, lost}` result,
  status instead of exceptions, invalid rows skipped), `join_board(p_code)` (normalises input,
  advisory-locked per-user rate limit: ≥10 failures in 15 min or ≥50 per day → `rate_limited`;
  a wrong code records the attempt and returns null instead of raising), `leave_board(p_board)`,
  `remove_member(p_board, p_user)` (owner; rotates the code), `rotate_invite(p_board)` (owner),
  `get_invite(p_board)` (owner), `delete_board(p_board)` (owner; absorbing `deleted_at`),
  `server_time_ms()`. `pamnot_info()` (also granted to `anon`) returns `{schema: 1}` so the app can
  tell whether the SQL was run.
- Realtime authorization: RLS on `realtime.messages` lets a member read and write topics
  `board-data:<id>` and `board-live:<id>` of their boards; the app uses private channels only.

## 7. Identity and setup

- **Anonymous auth** with a display name and colour (no e-mail: Supabase's built-in mail cannot
  reach teammates without custom SMTP). Each device is a separate member until e-mail linking
  arrives in a later version. Brute force on invites is infeasible at 50 bits plus the per-user rate
  limit plus Supabase's per-IP anonymous sign-in limit.
- **Invite text**: `PMN1.` + base64url(JSON `{u: url, k: publishableKey, c: code, t: title}`), no
  padding. The join screen finds `PMN1\.[A-Za-z0-9_-]{16,}` anywhere in pasted text, so a whole chat
  message can be pasted. It configures the app's server when none is set; it refuses an invite for a
  different server while one is set.
- **Owner setup wizard** (5 steps, copy buttons, bundled `assets/supabase/schema.sql`): create
  project → run SQL → enable anonymous sign-ins → paste Project URL + publishable/anon key → name and
  colour → Bağlan. URL normalisation (dashboard URL or bare project ref → `https://<ref>.supabase.co`,
  strip `/rest/v1` and trailing `/`, https only except localhost). Key validation: reject
  `sb_secret_…` and JWTs whose role is not `anon`; accept `sb_publishable_…` and anon JWTs. Checks in
  order with per-step messages: reach server, `pamnot_info`, anonymous sign-in, profile upsert.
- `CloudService` owns Supabase: `Supabase.initialize(url, publishableKey,
  authOptions: FlutterAuthClientOptions(detectSessionInUri: false),
  realtimeLifecycleOptions: RealtimeLifecycleOptions(disconnectAfterPause: Duration(seconds: 30)))`;
  never touches `Supabase.instance` before it is ready; switching servers = remove channels, sign
  out, dispose, initialise again. Config in KeyValueStore doc `cloud`; `--dart-define`
  `PAMNOT_SUPABASE_URL` / `PAMNOT_SUPABASE_KEY` as defaults (wizard steps 1–4 skipped).
- macOS needs `com.apple.security.network.client` in both entitlements files.

## 8. Canvas

- **No item widgets.** `BoardWorldPainter` draws lanes, cards, stickies and ink in order from a
  derived `BoardScene`. LOD 2 (scale ≥ 0.42, hysteresis 0.38): immediate mode with brute-force
  culling. LOD 1 / 0 (below 0.42 / 0.16): one cached `ui.Picture` per level, drawn with the viewport
  matrix; cards and stickies as rounded rects with greek bars, no text. No blurred shadows, no
  saveLayer, no `filterQuality` on transforms.
- **Single input path**: `RawGestureDetector({EagerGestureRecognizer})` around a
  `Listener(behavior: opaque)` feeding a `BoardInput` state machine with model hit-testing; items
  own no recognizers. Taps, double taps and long presses are timed by hand. The eager recognizer also
  beats the Cupertino back-swipe strip; the board page has an explicit back button.
- **Gestures**: touch — tap selects; dragging empty space or an unselected item pans; hold
  ≥250 ms (long-press 450 ms lifts with haptics) or drag an already-selected item to move it; two
  fingers pan/zoom; double-tap empty = new sticky; double-tap sticky = edit; double-tap card = card
  sheet. Mouse — drag item moves, drag empty = marquee, Space+drag or middle button pans, wheel pans
  (Shift = horizontal when dx == 0), Ctrl/Cmd+wheel and pinch zoom at the cursor; macOS ctrl+click =
  secondary. Trackpads: PointerPanZoom start/update/end; web: PointerScaleEvent. Stylus — draws with
  the current ink tool, its eraser end erases; once a stylus is seen (stylusOnly), fingers never draw.
  A second finger within 200 ms / 24 px of a finger stroke cancels the stroke and pinches. Palm:
  ignore touches with `radiusMajor > 24` in ink tools; ignore touches while a stylus is down.
- **Lanes**: one block at (`laneX`, `laneY`): lane width 300, gap 24, header 52, padding 12, card gap
  12, min lane height 420; cards stacked by order with measured heights (title max 3 lines). Dragging
  the header strip moves the block. Dropping a card: centre inside a lane → `{columnId, order}`
  (midpoint of neighbours); otherwise it animates back and, the first time, a snack explains that
  cards live in columns.
- **Stickies**: 200×200, text auto-fitted 28 → 12 (Nunito w600), colour from the pastel palette.
  "Karta dönüştür" turns one into a card (title = first line, notes = rest; one undo step).
- **Ink**: one stroke per item, points relative to the item origin; canvas width = toolbar width /
  scale (0.5–400); jitter threshold (0.5/scale)²; outlines built from a queue (3 ms/frame) with a
  polyline fallback; eraser removes whole strokes (radius 14/scale). Reuses `buildStrokePath`,
  `strokePaint`, `ActiveInk`, `InkStroke.hitTest`; not `InkPictureCache`.
- **Viewport**: scale 0.02–4 (min = clamp(fitScale·0.8, 0.02, 0.1)); world clamped to ±100,000;
  dot grid in screen space with one `drawRawPoints`, spacing 40·2^k so spacing·s ≥ 18 px, hidden
  below 0.15; first open zooms to fit; per-device view memory.
- **State**: a `BoardSession` per open board, outside AppScope, with separate notifiers (viewport,
  scene revision, lifted set, selection, hover, presence, active ink, tool). Painters subscribe via
  `repaint:`; no widget rebuilds while panning, zooming, drawing or dragging.
- **Editing**: phones edit stickies in a bottom sheet with PredictionBar; wide screens edit in
  place (screen-space TextField, no text scaling, auto-zoom so the font is ≥16 px on touch or ≥13 px
  with a pointer, PredictionBar above the keyboard, `resizeToAvoidBottomInset: false`). Cards always
  open the card sheet.
- **Toolbars**: phone — bottom pill [Seç][Not][Kart][Kalem][↶][⋯]; ≥600 dp — vertical pill on the
  left (Seç, Not, Kart | Kalem, Fosforlu, Silgi | Geri al, Yinele) and zoom controls bottom-right.
  Selection mini-toolbar: colours, Karta dönüştür, Kopyasını oluştur, Öne getir / Arkaya gönder, Sil.
- **Shortcuts** via Shortcuts + Actions whose `isEnabled` is false while editing text: V/N/K/P/F/E
  tools, Space pan, Shift+1 fit, Cmd/Ctrl ± zoom, Delete, Cmd/Ctrl+D, Cmd/Ctrl+Z / Shift+Z, Esc.
- **Performance gate**: a generated board with 5,000 items and 2,000 strokes; scripted pinch
  1 → 0.1 → 1, fling, drag of 200 items; p99 frame build ≤ 6 ms and raster ≤ 8 ms on an M1 device.

## 9. Kanban

Phone: `PageView(viewportFraction: 0.86)`; wide: 300 dp columns plus a ghost "+ Sütun ekle". Column
menu: rename, colour, done column switch, move left/right, delete (cards move to the neighbouring
column; the last column offers "delete the cards too"). "+ Kart ekle" inline field with quickParse
for the due date. Drag and drop (touch: long press 300 ms; mouse: drag) with an insertion line and
edge auto-scroll; a move across columns shows an undo snack `«title» → column`. A footer line notes
stickies/ink on the canvas. Card face: colour stripe, title (3 lines), due chip ("Gecikti · 12 Kas"
when overdue and not done), subtasks `☑ 2/5`, notes icon, assignee avatar, a check icon in done
columns. Card sheet: column chips, title, description (word prediction), due date, subtasks, colour,
assignee on shared boards; it commits once when it closes, by any means.

Accessibility: Kanban is the screen-reader view; cards expose custom actions (next/previous
column, up/down); the canvas has one summary label.

## 10. App integration

- Takip segments become `enum TrackSegment { tasks, habits, boards }`, persisted in AppSettings;
  icons only at ≥420 dp; a task notification forces the tasks segment.
- A sample board ("İlk panom 🌷") is seeded the first time Panolar is shown (`boardsSeeded`).
- Settings gains "Ortak çalışma". About text: data stays on the device except boards you share.

## 11. Module map

```
lib/boards/model/        hlc, board_item, board_doc, order          (pure Dart, shared)
lib/boards/board_editor.dart   ops, write groups, undo/redo, derived views
lib/boards/boards_repository.dart  persistence (documents, ink blobs, views, index)
lib/boards/boards_controller.dart  list, create, seed, open/close, connections
lib/boards/sync/         backend interface, BoardSync engine, Supabase backend
lib/boards/cloud/        CloudService, invite codec, setup wizard, share/join/members UI
lib/boards/canvas/       session, viewport, scene + lanes, painters, input, toolbars, editor
lib/boards/ui/           board list, new board sheet, board page, kanban, card face, card sheet
supabase/schema.sql      server schema (copied to assets/supabase/schema.sql)
```
