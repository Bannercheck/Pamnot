import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../l10n/board_strings.dart';
import '../../l10n/strings.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../../theme/pamnot_theme.dart';
import '../../ui/common/soft.dart';
import '../board_editor.dart';
import '../boards_controller.dart';
import '../boards_repository.dart';
import '../cloud/share_sheet.dart';
import '../model/board_doc.dart';
import 'board_page.dart';
import 'board_widgets.dart';
import 'new_board_sheet.dart';

/// "Davete katıl": paste an invite, then open the joined board.
Future<void> joinBoardFromInvite(BuildContext context) async {
  final boards = AppScope.of(context).boards;
  final id = await showJoinSheet(context, boards: boards);
  if (id != null && context.mounted) await BoardPage.open(context, id);
}

/// Takip › Panolar as slivers: tiles in one column below 560 dp and two
/// from 560 dp, the empty state, and the sample board the first time the
/// segment is shown. Listens to [BoardsController] directly (it is not an
/// app slice).
class BoardsSliver extends StatefulWidget {
  const BoardsSliver({super.key, required this.padding});

  final double padding;

  @override
  State<BoardsSliver> createState() => _BoardsSliverState();
}

class _BoardsSliverState extends State<BoardsSliver> {
  bool _seeding = false;

  /// Seeds "İlk panom 🌷" once, after the list has loaded (seeding before
  /// that would race the index load). The flag is set first, so a crash
  /// mid-way never seeds twice.
  void _maybeSeed(AppController app) {
    if (_seeding || app.settings.boardsSeeded || !app.boards.loaded) return;
    _seeding = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _seeding = false;
        return;
      }
      final s = S.of(context);
      app.updateSettings(app.settings.copyWith(boardsSeeded: true));
      try {
        await app.boards.seedSample(s);
      } finally {
        if (mounted) {
          setState(() => _seeding = false);
        } else {
          _seeding = false;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context, {Slice.settings});
    final boards = app.boards;
    return ListenableBuilder(
      listenable: boards,
      builder: (context, _) {
        final s = S.of(context);
        if (!boards.loaded || !app.settings.boardsSeeded || _seeding) {
          _maybeSeed(app);
          return const SliverToBoxAdapter(child: SizedBox(height: 160));
        }
        final list = boards.boards;
        if (list.isEmpty) {
          return SliverToBoxAdapter(
            child: EmptyState(
              emoji: '🗂️',
              text: s.boardsEmpty,
              action: Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => showNewBoardSheet(context),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(s.newBoard),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => joinBoardFromInvite(context),
                    icon: const Icon(Icons.group_add_outlined),
                    label: Text(s.haveInvite),
                  ),
                ],
              ),
            ),
          );
        }
        final now = app.now();
        return SliverLayoutBuilder(builder: (context, constraints) {
          final w = constraints.crossAxisExtent;
          final side = math.max(widget.padding, (w - 820) / 2);
          return SliverPadding(
            padding: EdgeInsets.fromLTRB(side, 12, side, 0),
            sliver: SliverMasonryGrid.count(
              crossAxisCount: w < 560 ? 1 : 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childCount: list.length,
              itemBuilder: (context, i) => BoardTile(key: ValueKey(list[i].id), board: list[i], now: now),
            ),
          );
        });
      },
    );
  }
}

/// One board on the list: pastel paper, title, where it lives, progress,
/// column dots with counts and when it last changed.
class BoardTile extends StatelessWidget {
  const BoardTile({super.key, required this.board, required this.now});

  final BoardSummary board;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final p = pastelAt(board.colorIndex);
    final muted = t.textTheme.labelMedium?.copyWith(color: c.onSurfaceVariant);
    final (IconData icon, String where) = switch (board.state) {
      BoardState.local => (Icons.smartphone_rounded, s.onDevice),
      BoardState.uploading || BoardState.shared => (Icons.group_rounded, s.sharedBoard),
      BoardState.deleted || BoardState.revoked => (Icons.lock_outline_rounded, s.readOnlyBoard),
    };
    final title = board.title.trim().isEmpty ? s.untitled : board.title;

    return GestureDetector(
      onSecondaryTap: () => showBoardActions(context, board),
      child: SoftCard(
        color: p.paper(t.brightness),
        padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
        onTap: () => BoardPage.open(context, board.id),
        onLongPress: () => showBoardActions(context, board),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.surfaceContainerLowest.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: c.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(where, style: muted),
                    ],
                  ),
                ),
              ],
            ),
            if (board.cardCount > 0) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: board.doneCount / board.cardCount,
                        minHeight: 6,
                        color: p.accent,
                        backgroundColor: p.accent.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(s.doneOfTotal(board.doneCount, board.cardCount), style: muted),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final (name, color, count, _) in board.columns)
                  Semantics(
                    label: '$name: $count',
                    child: ExcludeSemantics(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [PastelDot(color, size: 9), const SizedBox(width: 4), Text('$count', style: muted)],
                      ),
                    ),
                  ),
                Text('${board.columns.isEmpty ? '' : '· '}${relativeAgo(s, board.updatedAt, now)}', style: muted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens [id] briefly to change it from the list.
Future<void> _editBoard(BoardsController boards, String id, void Function(BoardEditor e) edit) async {
  final b = await boards.open(id);
  if (b == null) return;
  try {
    edit(b.editor);
  } finally {
    await boards.release(b);
  }
}

/// Long press or right click on a tile: rename, colour, share, remove.
Future<void> showBoardActions(BuildContext context, BoardSummary board) {
  final s = S.of(context);
  final boards = AppScope.of(context).boards;
  final readOnly = board.state == BoardState.deleted || board.state == BoardState.revoked;
  return showModalBottomSheet<void>(
    context: context,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!readOnly) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(s.rename),
                onTap: () async {
                  Navigator.pop(sheet);
                  final title = await promptText(context, title: s.rename, initial: board.title, hint: s.boardName);
                  if (title != null) await _editBoard(boards, board.id, (e) => e.setTitle(title));
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: PastelPicker(
                  selected: board.colorIndex,
                  onChanged: (i) {
                    Navigator.pop(sheet);
                    unawaited(_editBoard(boards, board.id, (e) => e.setColor(i)));
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_rounded),
                title: Text(s.share),
                onTap: () {
                  Navigator.pop(sheet);
                  unawaited(showShareSheet(context, boards: boards, boardId: board.id));
                },
              ),
            ],
            ListTile(
              leading: Icon(board.shared && !readOnly ? Icons.logout_rounded : Icons.delete_outline_rounded),
              title: Text(readOnly ? s.removeFromList : (board.shared ? s.removeSharedBoard : s.delete)),
              onTap: () {
                Navigator.pop(sheet);
                if (readOnly) {
                  unawaited(boards.removeLocal(board.id));
                } else {
                  unawaited(confirmRemoveBoard(context, boards: boards, boardId: board.id));
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}
