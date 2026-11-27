/// The kinds of record that iCloud sync carries.
enum RecordType { list, task, note, reminder, habit, meeting }

/// The key a record has in the sync index: `<type>:<id>`, e.g. `task:a1`.
String recordKey(RecordType type, String id) => '${type.name}:$id';

/// A CloudKit record zone: `personal` (notes, reminders, habits, meetings)
/// or `list-<id>` (a list and its tasks). A shared zone also names the
/// owner's user record, because it lives in the shared database.
class ZoneRef {
  const ZoneRef.private(this.name) : owner = null;
  const ZoneRef.shared(String this.owner, this.name);

  /// The owner's user record name; null in the private database.
  final String? owner;

  /// `personal` or `list-<id>`.
  final String name;

  bool get isShared => owner != null;

  static const personal = ZoneRef.private(_personalName);

  static const _personalName = 'personal';
  static const _listPrefix = 'list-';
  static const _sharedPrefix = 'shared:';

  /// CloudKit zone names are at most 255 characters; nothing longer is read.
  static const _maxLength = 255;

  /// Ids and owner record names: letters, digits, `_` and `-`. This keeps
  /// path pieces (`/`, `..`), spaces and separators out of zone names.
  static final _token = RegExp(r'^[A-Za-z0-9_-]+$');

  /// The zone of a local list: `work` → `list-work`; a received shared list
  /// `shared:<owner>:<id>` → the owner's `list-<id>`.
  static ZoneRef forList(String localListId) {
    if (isSharedListId(localListId)) {
      final rest = localListId.substring(_sharedPrefix.length);
      final colon = rest.indexOf(':');
      return ZoneRef.shared(rest.substring(0, colon), '$_listPrefix${rest.substring(colon + 1)}');
    }
    return ZoneRef.private('$_listPrefix$localListId');
  }

  /// A local list id is a received shared list: `shared:<owner>:<id>`.
  static bool isSharedListId(String listId) =>
      listId.startsWith(_sharedPrefix) && listId.indexOf(':', _sharedPrefix.length) >= 0;

  /// The local id of the list this zone holds; null for [personal].
  String? get localListId {
    if (!name.startsWith(_listPrefix)) return null;
    final id = name.substring(_listPrefix.length);
    return isShared ? '$_sharedPrefix$owner:$id' : id;
  }

  /// Reads `personal`, `list-<id>` or `shared:<owner>:list-<id>`; anything
  /// else (empty parts, unknown names, stray characters, too long) is null.
  static ZoneRef? parse(String s) {
    if (s.isEmpty || s.length > _maxLength) return null;
    if (s == _personalName) return personal;
    if (s.startsWith(_sharedPrefix)) {
      final parts = s.split(':');
      if (parts.length != 3 || !_token.hasMatch(parts[1]) || !_isListName(parts[2])) return null;
      return ZoneRef.shared(parts[1], parts[2]);
    }
    return _isListName(s) ? ZoneRef.private(s) : null;
  }

  static bool _isListName(String s) => s.startsWith(_listPrefix) && _token.hasMatch(s.substring(_listPrefix.length));

  /// The inverse of [parse].
  @override
  String toString() => isShared ? '$_sharedPrefix$owner:$name' : name;

  @override
  bool operator ==(Object other) => other is ZoneRef && other.owner == owner && other.name == name;

  @override
  int get hashCode => Object.hash(owner, name);
}
