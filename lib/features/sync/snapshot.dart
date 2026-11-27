import '../../models/task_list.dart';
import '../../state/app_controller.dart';
import 'zone_ref.dart';

/// One record as the app holds it now, ready for the sync index.
class SnapshotItem {
  const SnapshotItem(this.json, this.zone, {this.createdAt, this.pristine = false});

  final Map<String, Object?> json;
  final ZoneRef zone;

  /// The time the migration gives the record; null when it has none.
  final DateTime? createdAt;

  /// An untouched ready-made list: every device has the same one, so the
  /// migration dates it at `RecordIndex.pristineTime` and any edit wins.
  final bool pristine;
}

/// Every synced record of [app] by [recordKey], or only those of [only].
/// A task sits in its list's zone, a list in its own; notes, reminders and
/// habits in [ZoneRef.personal]. A note offers its `updatedAt` as
/// [SnapshotItem.createdAt]. Meetings are not part of the controller.
Map<String, SnapshotItem> snapshotApp(AppController app, {Set<RecordType>? only}) {
  bool wants(RecordType t) => only == null || only.contains(t);
  return {
    if (wants(RecordType.list))
      for (final l in app.lists)
        recordKey(RecordType.list, l.id): SnapshotItem(l.toJson(), ZoneRef.forList(l.id), pristine: _isPristine(l)),
    if (wants(RecordType.task))
      for (final t in app.tasks)
        recordKey(RecordType.task, t.id): SnapshotItem(t.toJson(), ZoneRef.forList(t.listId), createdAt: t.createdAt),
    if (wants(RecordType.note))
      for (final n in app.notes)
        recordKey(RecordType.note, n.id): SnapshotItem(n.toJson(), ZoneRef.personal, createdAt: n.updatedAt),
    if (wants(RecordType.reminder))
      for (final r in app.reminders)
        recordKey(RecordType.reminder, r.id): SnapshotItem(r.toJson(), ZoneRef.personal, createdAt: r.createdAt),
    if (wants(RecordType.habit))
      for (final h in app.habits)
        recordKey(RecordType.habit, h.id): SnapshotItem(h.toJson(), ZoneRef.personal, createdAt: h.createdAt),
  };
}

final _defaultsTr = {for (final l in TaskList.defaults(tr: true)) l.id: l};
final _defaultsEn = {for (final l in TaskList.defaults(tr: false)) l.id: l};

/// A ready-made list whose name is its Turkish or English default and whose
/// colour and icon were never changed.
bool _isPristine(TaskList l) {
  final tr = _defaultsTr[l.id];
  final en = _defaultsEn[l.id];
  if (!l.builtIn || tr == null || en == null) return false;
  return l.colorIndex == tr.colorIndex && l.icon == tr.icon && (l.name == tr.name || l.name == en.name);
}
