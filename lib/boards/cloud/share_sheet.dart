import 'package:flutter/material.dart';

import '../boards_controller.dart';

/// "Paylaş": set-up prompt, upload, invite text, members (DESIGN.md §7).
///
/// STUB: the collaboration UI replaces this body; the signature is the
/// contract the board page uses.
Future<void> showShareSheet(BuildContext context, {required BoardsController boards, required String boardId}) async {}

/// "Davete katıl": paste an invite, join, returns the joined board's id.
///
/// STUB, as above.
Future<String?> showJoinSheet(BuildContext context, {required BoardsController boards}) async => null;

/// Removing a board from the list: device-only boards are deleted; shared
/// boards offer "leave" (member) or "delete for everyone" (owner). Returns
/// true when the board is gone from this device.
///
/// STUB, as above: deletes device-only boards only.
Future<bool> confirmRemoveBoard(BuildContext context, {required BoardsController boards, required String boardId}) async {
  final s = boards.summary(boardId);
  if (s == null || s.shared) return false;
  await boards.removeLocal(boardId);
  return true;
}
