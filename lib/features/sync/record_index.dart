import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/store.dart';
import 'snapshot.dart';
import 'zone_ref.dart';

/// What the index knows about one record. Holds no user text: only a
/// fingerprint, a time and a zone.
class IndexEntry {
  const IndexEntry({
    required this.fp,
    required this.updatedAt,
    required this.zone,
    this.deleted = false,
    this.dirty = false,
  });

  /// [fingerprint] of the record's JSON when it was last seen.
  final String fp;

  /// When the record last changed (UTC); for a tombstone, when it was deleted.
  final DateTime updatedAt;

  /// A tombstone: the record was deleted; purged after
  /// [RecordIndex.tombstoneDays].
  final bool deleted;
  final ZoneRef zone;

  /// Changed here and not yet sent to iCloud.
  final bool dirty;
}

/// What one [RecordIndex.scan] found.
class IndexDiff {
  IndexDiff({Set<String> changed = const {}, Set<String> deleted = const {}, Map<String, ZoneRef> movedFrom = const {}})
      : changed = Set.unmodifiable(changed),
        deleted = Set.unmodifiable(deleted),
        movedFrom = Map.unmodifiable(movedFrom);

  /// New or changed records (including a tombstone brought back by Undo).
  final Set<String> changed;

  /// Records that disappeared and are now tombstones.
  final Set<String> deleted;

  /// For a changed record that moved zone: the zone it left.
  final Map<String, ZoneRef> movedFrom;

  bool get isEmpty => changed.isEmpty && deleted.isEmpty;
}

/// The local sync index: for every synced record its fingerprint, change
/// time, zone, tombstone and "not yet sent" flag, kept under [storeKey].
/// Comparing the app's [snapshotApp] with it tells which records changed.
class RecordIndex {
  RecordIndex(this.store, {required this.now});

  final KeyValueStore store;
  final DateTime Function() now;

  static const storeKey = 'sync_index';
  static const tombstoneDays = 30;

  /// The migration date of an untouched ready-made list: older than any
  /// real edit, so every device's edit wins over it.
  static final pristineTime = DateTime.utc(2000);

  static const _version = 1;
  static final _types = {for (final t in RecordType.values) t.name: t};

  final Map<String, IndexEntry> _entries = {};
  bool _migrated = false;
  Future<void> _lastWrite = Future.value();

  /// Whether the existing records were given their first dates.
  bool get migrated => _migrated;

  IndexEntry? operator [](String key) => _entries[key];

  Iterable<String> get dirtyKeys => _entries.keys.where((k) => _entries[k]!.dirty);

  DateTime _utcNow() => now().toUtc();

  /// Reads the saved index. A missing or unreadable document leaves the
  /// index empty and not [migrated], so the next [scan] migrates again.
  Future<void> load() async {
    _entries.clear();
    _migrated = false;
    final String? doc;
    try {
      doc = await store.read(storeKey);
    } catch (e) {
      debugPrint('Sync index unreadable: ${e.runtimeType}');
      return;
    }
    if (doc == null) return;
    try {
      final j = jsonDecode(doc) as Map;
      final entries = (j['entries'] as Map).cast<String, Object?>();
      final read = <String, IndexEntry>{
        for (final MapEntry(:key, :value) in entries.entries) key: _decode(key, (value! as Map).cast<String, Object?>()),
      };
      _entries.addAll(read);
      _migrated = j['migrated'] == true;
    } catch (e) {
      debugPrint('Sync index damaged; it will be rebuilt: ${e.runtimeType}');
      _entries.clear();
    }
  }

  static IndexEntry _decode(String key, Map<String, Object?> j) {
    final zone = ZoneRef.parse(j['z']! as String);
    if (_typeOf(key) == null || zone == null) throw const FormatException('bad entry');
    return IndexEntry(
      fp: j['f']! as String,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(j['u']! as int, isUtc: true),
      zone: zone,
      deleted: j['d'] == true,
      dirty: j['k'] == true,
    );
  }

  static RecordType? _typeOf(String key) {
    final colon = key.indexOf(':');
    return colon <= 0 || colon == key.length - 1 ? null : _types[key.substring(0, colon)];
  }

  /// Compares [snapshot] with the index, looking only at the record types in
  /// [only] (all when null), and records what changed. The first scan
  /// before [migrated] dates every record instead and ignores [only].
  IndexDiff scan(Map<String, SnapshotItem> snapshot, {Set<RecordType>? only}) {
    if (!_migrated) return _migrate(snapshot);
    bool wants(String key) {
      final t = _typeOf(key);
      return t != null && (only == null || only.contains(t));
    }

    final stamp = _utcNow();
    final changed = <String>{};
    final movedFrom = <String, ZoneRef>{};
    for (final MapEntry(:key, value: item) in snapshot.entries) {
      if (!wants(key)) continue;
      final fp = fingerprint(item.json);
      final old = _entries[key];
      if (old != null && !old.deleted && old.fp == fp && old.zone == item.zone) continue;
      if (old != null && old.zone != item.zone) movedFrom[key] = old.zone;
      _entries[key] = IndexEntry(fp: fp, updatedAt: stamp, zone: item.zone, dirty: true);
      changed.add(key);
    }
    final deleted = <String>{};
    for (final MapEntry(:key, value: e) in _entries.entries) {
      if (e.deleted || snapshot.containsKey(key) || !wants(key)) continue;
      deleted.add(key);
    }
    for (final key in deleted) {
      final e = _entries[key]!;
      _entries[key] = IndexEntry(fp: e.fp, updatedAt: stamp, zone: e.zone, deleted: true, dirty: true);
    }
    return IndexDiff(changed: changed, deleted: deleted, movedFrom: movedFrom);
  }

  IndexDiff _migrate(Map<String, SnapshotItem> snapshot) {
    final stamp = _utcNow();
    _entries.clear();
    for (final MapEntry(:key, value: item) in snapshot.entries) {
      if (_typeOf(key) == null) continue;
      final at = item.pristine ? pristineTime : (item.createdAt?.toUtc() ?? stamp);
      _entries[key] = IndexEntry(fp: fingerprint(item.json), updatedAt: at, zone: item.zone, dirty: true);
    }
    _migrated = true;
    unawaited(save().catchError((Object e) => debugPrint('Sync index not saved: ${e.runtimeType}')));
    return IndexDiff(changed: _entries.keys.toSet());
  }

  /// Takes a record from iCloud as the current state; it is not dirty.
  /// A null [item] is a deletion of a record the index knows.
  void adopt(String key, SnapshotItem? item, {required DateTime updatedAt, bool deleted = false}) {
    final old = _entries[key];
    if (item == null && old == null) return;
    _entries[key] = IndexEntry(
      fp: item == null ? old!.fp : fingerprint(item.json),
      updatedAt: updatedAt.toUtc(),
      zone: item?.zone ?? old!.zone,
      deleted: deleted || item == null,
    );
  }

  /// iCloud accepted these records.
  void markSent(Iterable<String> keys) {
    for (final key in keys) {
      final e = _entries[key];
      if (e == null || !e.dirty) continue;
      _entries[key] = IndexEntry(fp: e.fp, updatedAt: e.updatedAt, zone: e.zone, deleted: e.deleted);
    }
  }

  /// Everything has to be sent again (the iCloud account changed).
  void markAllDirty() {
    _entries.updateAll(
      (_, e) => e.dirty ? e : IndexEntry(fp: e.fp, updatedAt: e.updatedAt, zone: e.zone, deleted: e.deleted, dirty: true),
    );
  }

  /// Drops tombstones older than [tombstoneDays] and returns their keys.
  List<String> purge() {
    final cutoff = _utcNow().subtract(const Duration(days: tombstoneDays));
    final old = [
      for (final MapEntry(:key, value: e) in _entries.entries)
        if (e.deleted && e.updatedAt.isBefore(cutoff)) key,
    ];
    old.forEach(_entries.remove);
    return old;
  }

  /// Writes the index. Writes happen in call order; each holds the state at
  /// the moment of its call.
  Future<void> save() {
    final doc = jsonEncode({
      'v': _version,
      'migrated': _migrated,
      'entries': {
        for (final MapEntry(:key, value: e) in _entries.entries)
          key: {
            'f': e.fp,
            'u': e.updatedAt.millisecondsSinceEpoch,
            'd': e.deleted,
            'z': e.zone.toString(),
            'k': e.dirty,
          },
      },
    });
    final write = _lastWrite.catchError((Object _) {}).then((_) => store.write(storeKey, doc));
    _lastWrite = write;
    return write;
  }
}

/// A short, stable fingerprint of [json]: 32-bit FNV-1a over the UTF-8 bytes
/// of `jsonEncode(json)` as 8 hex digits, then `:` and the byte length.
/// Uses only exact integer arithmetic below 2^53, so web gives the same value.
String fingerprint(Map<String, Object?> json) {
  final bytes = utf8.encode(jsonEncode(json));
  const prime = 0x01000193; // 2^24 + 0x193
  const mod = 0x100000000;
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h ^= b;
    // h * prime mod 2^32, split so no product exceeds 2^53.
    h = (h * (prime & 0xffffff) + (h % 0x100) * 0x1000000) % mod;
  }
  return '${h.toRadixString(16).padLeft(8, '0')}:${bytes.length}';
}
