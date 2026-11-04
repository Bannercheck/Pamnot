import 'board_item.dart';
import 'hlc.dart';

enum BoardState { local, uploading, shared, deleted, revoked }

BoardState boardStateFromName(String? s) =>
    BoardState.values.firstWhere((v) => v.name == s, orElse: () => BoardState.local);

/// The server and user a shared board belongs to. Sync runs only while the
/// current session matches it.
class BoardAccount {
  const BoardAccount({required this.host, required this.userId});

  final String host;
  final String userId;

  Map<String, Object?> toJson() => {'host': host, 'userId': userId};

  static BoardAccount? fromJson(Object? j) {
    if (j is! Map) return null;
    final host = j['host'], user = j['userId'];
    if (host is! String || user is! String) return null;
    return BoardAccount(host: host, userId: user);
  }

  @override
  bool operator ==(Object other) => other is BoardAccount && other.host == host && other.userId == userId;

  @override
  int get hashCode => Object.hash(host, userId);
}

/// A row as the server stores it: field values and field HLCs.
class RemoteRow {
  const RemoteRow({
    required this.id,
    required this.kind,
    required this.data,
    required this.fh,
    this.rev,
    this.updatedBy,
    this.updatedAt,
  });

  final String id;
  final String kind;
  final Map<String, Object?> data;
  final Map<String, String> fh;
  final int? rev;
  final String? updatedBy;
  final DateTime? updatedAt;

  /// Parses a PostgREST / realtime record. Returns null when `data`, `fh` or
  /// `rev` is missing (a truncated record must never be merged).
  static RemoteRow? tryParse(Map<String, Object?> r, {bool requireRev = true}) {
    final id = r['id'], kind = r['kind'], data = r['data'], fh = r['fh'], rev = r['rev'];
    if (id is! String || kind is! String || data is! Map || fh is! Map) return null;
    if (requireRev && rev is! num) return null;
    return RemoteRow(
      id: id,
      kind: kind,
      data: data.cast<String, Object?>(),
      fh: {for (final e in fh.entries) if (e.value is String) e.key as String: e.value as String},
      rev: (rev as num?)?.toInt(),
      updatedBy: r['updated_by'] as String?,
      updatedAt: r['updated_at'] is String ? DateTime.tryParse(r['updated_at'] as String) : null,
    );
  }
}

/// The server's answer for one pushed row.
class PushAck {
  const PushAck({required this.id, required this.fh, this.lost = const {}, this.invalid = false});

  final String id;

  /// The server's field HLCs after the merge.
  final Map<String, String> fh;

  /// Server values for fields where this client's write was older.
  final Map<String, Object?> lost;
  final bool invalid;
}

class MergeResult {
  const MergeResult({required this.changed, required this.incomplete});

  /// Item ids whose visible values changed.
  final Set<String> changed;

  /// A field was newer but its value was missing: ask for a catch-up.
  final bool incomplete;
}

/// A whole board as stored on this device: one document, one atomic write.
class BoardDoc {
  BoardDoc({
    required this.id,
    this.state = BoardState.local,
    this.account,
    this.cursor = 0,
    Map<String, BoardItem>? items,
  }) : items = items ?? {};

  String id;
  BoardState state;
  BoardAccount? account;

  /// Highest server `rev` applied in order.
  int cursor;
  final Map<String, BoardItem> items;

  bool get isShared => state == BoardState.uploading || state == BoardState.shared;
  bool get readOnly => state == BoardState.deleted || state == BoardState.revoked;

  BoardItem? get meta => items[id];

  /// Applies a local edit: every field gets [hlc] and is marked dirty.
  BoardItem write(String itemId, ItemKind kind, Map<String, Object?> fields, String hlc) {
    final it = items.putIfAbsent(itemId, () => BoardItem(id: itemId, kind: kind));
    for (final e in fields.entries) {
      it.f[e.key] = e.value;
      it.h[e.key] = hlc;
      it.d.add(e.key);
    }
    return it;
  }

  /// Per-field last-writer-wins merge of server rows. Idempotent and
  /// commutative, so pulls, realtime events and duplicates mix freely.
  MergeResult merge(Iterable<RemoteRow> rows, HlcClock clock) {
    final changed = <String>{};
    var incomplete = false;
    for (final r in rows) {
      var it = items[r.id];
      if (it == null) {
        final kind = itemKindFromName(r.kind);
        if (kind == null) continue;
        it = BoardItem(id: r.id, kind: kind);
        items[r.id] = it;
      }
      for (final e in r.fh.entries) {
        final k = e.key, rh = e.value;
        clock.observe(rh);
        final lh = it.h[k];
        final c = lh == null ? 1 : rh.compareTo(lh);
        if (c > 0) {
          if (!r.data.containsKey(k)) {
            incomplete = true;
            continue;
          }
          it.f[k] = r.data[k];
          it.h[k] = rh;
          it.d.remove(k);
          changed.add(r.id);
        } else if (c == 0) {
          it.d.remove(k);
        }
      }
    }
    return MergeResult(changed: changed, incomplete: incomplete);
  }

  /// Rows to push: dirty fields of every item, with what was sent recorded in
  /// [sent] (`itemId → field → hlc`) for [applyAcks].
  List<Map<String, Object?>> dirtyRows(Map<String, Map<String, String>> sent, {int maxRows = 200, int maxBytes = 256 * 1024}) {
    final out = <Map<String, Object?>>[];
    var bytes = 0;
    for (final it in items.values) {
      if (it.d.isEmpty) continue;
      final data = <String, Object?>{};
      final fh = <String, String>{};
      var size = 64;
      for (final k in it.d) {
        final h = it.h[k];
        if (h == null) continue;
        // Ink strokes are pushed only once they are loaded into memory.
        if (k == F.strokes && it.f[k] == null) continue;
        data[k] = it.f[k];
        fh[k] = h;
        final v = it.f[k];
        size += k.length + 40 + (v is String ? v.length : 16);
      }
      if (fh.isEmpty) continue;
      if (out.isNotEmpty && (out.length >= maxRows || bytes + size > maxBytes)) break;
      out.add({'id': it.id, 'kind': it.kind.name, 'data': data, 'fh': fh});
      sent[it.id] = fh;
      bytes += size;
    }
    return out;
  }

  /// Clears dirty fields the server confirmed; keeps fields edited again
  /// while the push was in flight. Returns ids whose values changed.
  Set<String> applyAcks(Map<String, Map<String, String>> sent, Iterable<PushAck> acks) {
    final changed = <String>{};
    for (final a in acks) {
      final it = items[a.id];
      final s = sent[a.id];
      if (it == null || s == null) continue;
      if (a.invalid) {
        // The server will never accept this row; stop retrying it.
        it.d.removeAll(s.keys);
        continue;
      }
      for (final k in s.keys) {
        final server = a.fh[k];
        final local = it.h[k];
        if (server == null || local == null) continue;
        if (server == local) {
          it.d.remove(k);
        } else if (server.compareTo(local) > 0 && a.lost.containsKey(k)) {
          it.f[k] = a.lost[k];
          it.h[k] = server;
          it.d.remove(k);
          changed.add(a.id);
        }
      }
    }
    return changed;
  }

  int get pendingCount => items.values.where((i) => i.d.isNotEmpty).length;

  void clearDirty() {
    for (final it in items.values) {
      it.d.clear();
    }
  }

  /// Turns a device-only board into one being uploaded: tombstones go,
  /// every live field becomes dirty, the cursor restarts.
  void prepareUpload(BoardAccount account) {
    items.removeWhere((_, it) => it.deleted);
    for (final it in items.values) {
      it.d
        ..clear()
        ..addAll(it.f.keys.where((k) => it.h.containsKey(k)));
    }
    state = BoardState.uploading;
    this.account = account;
    cursor = 0;
  }

  /// Gives the board a new id (after an id collision on upload). The meta
  /// item follows the board id.
  void remint(String newId) {
    final meta = items.remove(id);
    id = newId;
    if (meta != null) {
      items[newId] = BoardItem(id: newId, kind: ItemKind.meta, f: meta.f, h: meta.h, d: meta.d);
    }
  }

  Map<String, Object?> toJson() => {
        'v': 1,
        'id': id,
        'state': state.name,
        if (account != null) 'account': account!.toJson(),
        'cursor': cursor,
        'items': {for (final it in items.values) it.id: it.toJson()},
      };

  static BoardDoc? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! String) return null;
    final items = <String, BoardItem>{};
    final raw = j['items'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final it = BoardItem.fromJson(e.key as String, e.value);
        if (it != null) items[it.id] = it;
      }
    }
    return BoardDoc(
      id: id,
      state: boardStateFromName(j['state'] as String?),
      account: BoardAccount.fromJson(j['account']),
      cursor: (j['cursor'] as num?)?.toInt() ?? 0,
      items: items,
    );
  }

  /// Feeds every stored HLC to [clock] so new ticks sort after them, even if
  /// the device clock went back.
  void observeAll(HlcClock clock) {
    for (final it in items.values) {
      for (final h in it.h.values) {
        clock.observe(h);
      }
    }
  }
}
