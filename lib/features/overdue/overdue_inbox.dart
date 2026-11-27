import 'dart:convert';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/store.dart';
import '../../state/app_controller.dart';

/// Task ids closed from a final notice's Done action while the app was in
/// the background. The background isolate adds; the app takes and applies.
class OverdueInbox {
  OverdueInbox(this.store);

  final KeyValueStore store;

  static const storeKey = 'overdue_done';

  /// The app's port; a background add pings it so the app applies at once.
  static const portName = 'app.pamnot.overdue';

  /// At most this many ids are kept; the oldest go first.
  static const maxIds = 200;

  /// Remembers [taskId] once.
  Future<void> add(String taskId) async {
    final ids = await _read()
      ..remove(taskId)
      ..add(taskId);
    final kept = ids.length > maxIds ? ids.sublist(ids.length - maxIds) : ids;
    await store.write(storeKey, jsonEncode(kept));
  }

  /// The remembered ids, oldest first; the document is deleted.
  Future<List<String>> take() async {
    final ids = await _read();
    await store.delete(storeKey);
    return ids;
  }

  /// A missing or damaged document reads as empty.
  Future<List<String>> _read() async {
    final raw = await store.read(storeKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final j = jsonDecode(raw);
      if (j is! List) return [];
      return {
        for (final e in j)
          if (e is String && e.isNotEmpty) e,
      }.toList();
    } on FormatException {
      return [];
    }
  }
}

/// Completes the tasks in [inbox]; unknown and finished ones are skipped.
/// Returns how many were completed.
Future<int> applyOverdueInbox(AppController app, OverdueInbox inbox) async {
  var n = 0;
  for (final id in await inbox.take()) {
    if (app.completeTask(id)) n++;
  }
  return n;
}

/// The Done action of a final notice, run in a background isolate: it only
/// records the task id and pings the app if it is running.
@pragma('vm:entry-point')
Future<void> overdueBackgroundAction(NotificationResponse r) async {
  final payload = r.payload;
  if (r.actionId != 'done' || payload == null || !payload.startsWith('o:') || payload.startsWith('o:sum:')) return;
  final id = payload.substring(2);
  if (id.isEmpty) return;
  try {
    await OverdueInbox(KeyValueStore.platformDefault()).add(id);
  } catch (e) {
    debugPrint('overdue: inbox write failed (${e.runtimeType})');
    return;
  }
  IsolateNameServer.lookupPortByName(OverdueInbox.portName)?.send(null);
}
