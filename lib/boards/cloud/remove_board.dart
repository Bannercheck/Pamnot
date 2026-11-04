import 'package:flutter/material.dart';

import '../../l10n/collab_strings.dart';
import '../../l10n/strings.dart';
import '../boards_controller.dart';
import '../model/board_doc.dart';
import '../sync/backend.dart';
import 'cloud_scope.dart';
import 'cloud_widgets.dart';

/// Removing a board from the list: device-only boards are deleted; shared
/// boards offer "leave" (member) or "delete for everyone" (owner); a board
/// that was deleted or revoked can be kept as a device-only copy. Returns
/// true when the board is gone from this device.
Future<bool> confirmRemoveBoard(BuildContext context, {required BoardsController boards, required String boardId}) async {
  final s = S.of(context);
  final summary = boards.summary(boardId);
  if (summary == null) return false;
  final title = summary.title;

  switch (summary.state) {
    case BoardState.local:
      final ok = await confirmCloudAction(
        context,
        title: s.deleteBoardTitle,
        body: s.deleteLocalBody(title),
        confirm: s.delete,
        destructive: true,
      );
      if (!ok) return false;
      await boards.removeLocal(boardId);
      return true;

    case BoardState.deleted:
    case BoardState.revoked:
      final choice = await showDialog<_GoneChoice>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.notSharedAnymore),
          content: Text(summary.state == BoardState.deleted ? s.boardDeletedByOwner : s.accessRemoved),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
            TextButton(onPressed: () => Navigator.pop(context, _GoneChoice.keep), child: Text(s.keepLocalCopy)),
            FilledButton(onPressed: () => Navigator.pop(context, _GoneChoice.delete), child: Text(s.removeFromDevice)),
          ],
        ),
      );
      if (choice == null) return false;
      if (choice == _GoneChoice.keep) await boards.saveLocalCopy(boardId);
      await boards.removeLocal(boardId);
      return true;

    case BoardState.uploading:
    case BoardState.shared:
      final cloud = CloudScope.read(context);
      final backend = cloud?.backend, me = cloud?.account;
      if (backend == null || me == null || summary.account != me) {
        showCloudSnack(context, s.needsInternet);
        return false;
      }
      final BoardStatusInfo? status;
      try {
        status = await backend.boardStatus(boardId);
      } on Exception {
        if (context.mounted) showCloudSnack(context, s.needsInternet);
        return false;
      }
      if (!context.mounted) return false;
      if (status == null && summary.state == BoardState.shared) {
        // Removed in the meantime: nothing to leave on the server.
        final ok = await confirmCloudAction(context,
            title: s.notSharedAnymore, body: s.accessRemoved, confirm: s.removeFromDevice, destructive: true);
        if (!ok) return false;
        await boards.removeLocal(boardId);
        return true;
      }
      // Never created on the server yet (upload still pending) counts as ours.
      final owner = status == null || status.ownerId == me.userId;
      final ok = await confirmCloudAction(
        context,
        title: owner ? s.deleteForEveryone : s.leaveBoard,
        body: owner ? s.deleteForEveryoneBody(title) : s.leaveBody(title),
        confirm: owner ? s.deleteForEveryone : s.leaveBoard,
        destructive: true,
      );
      if (!ok) return false;
      try {
        if (owner) {
          if (status != null) await backend.deleteBoard(boardId);
        } else {
          await backend.leaveBoard(boardId);
        }
      } on AccessDenied {
        // Already gone for us on the server; just tidy up here.
      } on Exception {
        if (context.mounted) showCloudSnack(context, s.needsInternet);
        return false;
      }
      await boards.removeLocal(boardId);
      return true;
  }
}

enum _GoneChoice { keep, delete }
