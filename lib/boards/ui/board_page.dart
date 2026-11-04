import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/board_strings.dart';
import '../../l10n/strings.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/common/soft.dart';
import '../boards_controller.dart';
import '../boards_repository.dart';
import '../canvas/board_canvas_view.dart';
import '../cloud/share_sheet.dart';
import '../connection.dart';
import '../model/board_doc.dart';
import 'board_widgets.dart';
import 'card_sheet.dart';
import 'kanban_view.dart';

enum _BoardAction { share, members, rename, color, remove }

/// A board, full screen above the tabs (ux_specs §4): a top bar with the
/// title, the Tuval | Kanban switch, presence and sync, and one of the two
/// views below it. The board is opened through [BoardsController.open] and
/// released when the page goes.
class BoardPage extends StatefulWidget {
  const BoardPage({super.key, required this.boardId});

  final String boardId;

  static Future<void> open(BuildContext context, String boardId) => Navigator.of(context, rootNavigator: true)
      .push(MaterialPageRoute<void>(builder: (_) => BoardPage(boardId: boardId)));

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> {
  late final AppController _app = AppScope.of(context);
  BoardsController get _boards => _app.boards;

  OpenBoard? _board;
  BoardConnection? _connection;
  BoardViewState? _viewState;
  String _view = 'kanban';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final board = await _boards.open(widget.boardId);
    final saved = board == null ? null : await _boards.loadView(widget.boardId);
    if (!mounted) {
      if (board != null) unawaited(_boards.release(board));
      return;
    }
    // First visit on this device: Kanban on phones, the canvas from 600 dp.
    final phone = MediaQuery.sizeOf(context).width < 600;
    setState(() {
      _board = board;
      _viewState = saved;
      _view = saved?.view ?? (phone ? 'kanban' : 'canvas');
      _loading = false;
    });
    if (board != null) {
      board.editor.addListener(_onEditor);
      _connection = board.connection;
      board.connection.setActivity(view: _view);
    }
  }

  @override
  void dispose() {
    final b = _board;
    if (b != null) {
      b.editor.removeListener(_onEditor);
      // Removing the board from the device (Sil / Panodan ayrıl) already
      // closed it; release only what is still open.
      if (identical(_boards.openBoard(b.id), b)) unawaited(_boards.release(b));
    }
    super.dispose();
  }

  /// A new connection (sign-in, server change) has to hear what we show.
  void _onEditor() {
    final b = _board;
    if (b == null || identical(b.connection, _connection)) return;
    _connection = b.connection;
    b.connection.setActivity(view: _view);
  }

  void _setView(String view) {
    final b = _board;
    if (b == null || view == _view) return;
    setState(() => _view = view);
    _viewState = (_viewState ?? BoardViewState(view: view)).copyWith(view: view);
    _boards.saveView(b.id, _viewState!);
    b.connection.setActivity(view: view);
  }

  /// The canvas reports its viewport when it settles; no rebuild here. It
  /// also reports once while being disposed after a switch to Kanban, so the
  /// page's current view is kept.
  void _onViewChanged(BoardViewState v) {
    final b = _board;
    if (b == null) return;
    _viewState = v.copyWith(view: _view);
    _boards.saveView(b.id, _viewState!);
  }

  void _onStylus() {
    final st = _app.settings;
    if (st.autoStylusOnly && !st.stylusOnly) {
      _app.updateSettings(st.copyWith(stylusOnly: true));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).stylusOnlyOn)));
    }
  }

  Future<void> _rename() async {
    final b = _board;
    if (b == null) return;
    final s = S.of(context);
    final title = await promptText(context, title: s.rename, initial: b.editor.title, hint: s.boardName);
    if (title != null) b.editor.setTitle(title);
  }

  Future<void> _onAction(_BoardAction a) async {
    final b = _board;
    if (b == null) return;
    switch (a) {
      case _BoardAction.share:
      case _BoardAction.members:
        await showShareSheet(context, boards: _boards, boardId: b.id);
      case _BoardAction.rename:
        await _rename();
      case _BoardAction.color:
        final i = await pickPastel(context, selected: b.editor.colorIndex);
        if (i != null) b.editor.setColor(i);
      case _BoardAction.remove:
        final nav = Navigator.of(context);
        if (b.editor.readOnly) {
          await _boards.removeLocal(b.id);
          nav.pop();
          return;
        }
        final gone = await confirmRemoveBoard(context, boards: _boards, boardId: b.id);
        if (gone && mounted) nav.pop();
    }
  }

  Future<void> _keepCopy() async {
    final b = _board;
    if (b == null) return;
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final id = await _boards.saveLocalCopy(b.id);
    if (id == null || !mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(s.copySaved)));
    unawaited(nav.pushReplacement(MaterialPageRoute<void>(builder: (_) => BoardPage(boardId: id))));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final board = _board;
    if (board == null) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: _loading ? const SizedBox.shrink() : EmptyState(emoji: '🗂️', text: s.boardNotFound),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 600;
    return BoardScope(
      board: board,
      view: _view,
      child: Builder(
        builder: (context) => Scaffold(
          // The canvas keeps its size under the keyboard; Kanban pads itself.
          resizeToAvoidBottomInset: false,
          body: Column(
            children: [
              _topBar(context, board, wide),
              _readOnlyBanner(board),
              Expanded(
                child: KeyedSubtree(
                  key: ValueKey(_view),
                  child: _view == 'canvas'
                      ? _canvas(board)
                      : KanbanView(
                          board: board,
                          onOpenCard: (id) => showCardSheet(context, board, id),
                          onShowCanvas: () => _setView('canvas'),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _canvas(OpenBoard board) => Builder(builder: (context) {
        // Only this subtree follows settings (stylus-only).
        final settings = AppScope.of(context, {Slice.settings}).settings;
        return BoardCanvasView(
          board: board,
          viewState: _viewState,
          onViewChanged: _onViewChanged,
          onOpenCard: (id) => showCardSheet(context, board, id),
          stylusOnly: settings.stylusOnly,
          onStylusDetected: _onStylus,
        );
      });

  Widget _topBar(BuildContext context, OpenBoard board, bool wide) {
    final s = S.of(context);
    final t = Theme.of(context);
    final e = board.editor;
    return Material(
      color: t.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 60,
          child: EditorSelector<(String, int, bool, bool)>(
            editor: e,
            select: (e) => (e.title, e.colorIndex, e.readOnly, e.doc.isShared),
            builder: (context, v) {
              final (title, color, readOnly, shared) = v;
              return Row(
                children: [
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: readOnly ? null : _rename,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          child: Row(
                            children: [
                              PastelDot(color, size: 12),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  title.trim().isEmpty ? s.untitled : title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.textTheme.titleLarge,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: [
                      ButtonSegment(
                        value: 'canvas',
                        icon: const Icon(Icons.gesture_rounded),
                        label: wide ? Text(s.canvasView) : null,
                        tooltip: wide ? null : s.canvasView,
                      ),
                      ButtonSegment(
                        value: 'kanban',
                        icon: const Icon(Icons.view_kanban_outlined),
                        label: wide ? Text(s.kanbanView) : null,
                        tooltip: wide ? null : s.kanbanView,
                      ),
                    ],
                    selected: {_view},
                    onSelectionChanged: (v) => _setView(v.first),
                  ),
                  const SizedBox(width: 4),
                  _Presence(board: board, max: wide ? 3 : 2, onMembers: () => _onAction(_BoardAction.members)),
                  if (wide && !readOnly) ...[
                    const SizedBox(width: 4),
                    FilledButton.tonalIcon(
                      onPressed: () => _onAction(_BoardAction.share),
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: Text(s.share),
                    ),
                  ],
                  PopupMenuButton<_BoardAction>(
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (a) => unawaited(_onAction(a)),
                    itemBuilder: (_) {
                      PopupMenuItem<_BoardAction> item(_BoardAction a, IconData icon, String label) => PopupMenuItem(
                            value: a,
                            child: Row(children: [
                              Icon(icon, size: 20),
                              const SizedBox(width: 12),
                              Flexible(child: Text(label)),
                            ]),
                          );
                      return [
                        if (!wide && !readOnly) item(_BoardAction.share, Icons.person_add_alt_1_rounded, s.share),
                        if (shared && !readOnly) item(_BoardAction.members, Icons.group_outlined, s.members),
                        if (!readOnly) item(_BoardAction.rename, Icons.edit_outlined, s.rename),
                        if (!readOnly) item(_BoardAction.color, Icons.palette_outlined, s.color),
                        if (!readOnly) const PopupMenuDivider(),
                        if (readOnly)
                          item(_BoardAction.remove, Icons.delete_outline_rounded, s.removeFromList)
                        else if (shared)
                          item(_BoardAction.remove, Icons.logout_rounded, s.removeSharedBoard)
                        else
                          item(_BoardAction.remove, Icons.delete_outline_rounded, s.delete),
                      ];
                    },
                  ),
                  const SizedBox(width: 4),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _readOnlyBanner(OpenBoard board) => EditorSelector<BoardState>(
        editor: board.editor,
        select: (e) => e.doc.state,
        builder: (context, state) {
          if (state != BoardState.deleted && state != BoardState.revoked) return const SizedBox.shrink();
          final s = S.of(context);
          final t = Theme.of(context);
          final c = t.colorScheme;
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              decoration: BoxDecoration(color: c.secondaryContainer, borderRadius: BorderRadius.circular(20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline_rounded, color: c.onSecondaryContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          state == BoardState.deleted ? s.boardDeletedBanner : s.boardRevokedBanner,
                          style: t.textTheme.bodyMedium?.copyWith(color: c.onSecondaryContainer),
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    children: [
                      TextButton(onPressed: () => _onAction(_BoardAction.remove), child: Text(s.removeFromList)),
                      TextButton(onPressed: _keepCopy, child: Text(s.keepCopy)),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
}

/// Others here now and the sync state; both follow the board's current
/// connection (it is replaced on sign-in or a server change).
class _Presence extends StatelessWidget {
  const _Presence({required this.board, required this.max, required this.onMembers});

  final OpenBoard board;
  final int max;
  final VoidCallback onMembers;

  @override
  Widget build(BuildContext context) => EditorSelector<BoardConnection>(
        editor: board.editor,
        select: (_) => board.connection,
        builder: (context, conn) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<List<Peer>>(
              valueListenable: conn.peers,
              builder: (context, peers, _) => PeerAvatars(peers: peers, max: max, onTap: onMembers),
            ),
            ValueListenableBuilder<SyncState>(
              valueListenable: conn.state,
              builder: (context, st, _) => _SyncButton(state: st, onRetry: conn.retry),
            ),
          ],
        ),
      );
}

class _SyncButton extends StatelessWidget {
  const _SyncButton({required this.state, required this.onRetry});

  final SyncState state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = Theme.of(context).colorScheme;
    final (IconData? icon, String tip) = switch (state.status) {
      SyncStatus.local => (null, ''),
      SyncStatus.synced => (Icons.cloud_done_outlined, s.syncUpToDate),
      SyncStatus.sending => (Icons.cloud_upload_outlined, s.syncSending(state.pending)),
      SyncStatus.offline => (Icons.cloud_off_outlined, s.syncOffline),
      SyncStatus.error => (Icons.error_outline_rounded, s.syncError),
      SyncStatus.deleted || SyncStatus.revoked => (Icons.lock_outline_rounded, s.readOnlyBoard),
    };
    if (icon == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: tip,
      onPressed: () => unawaited(onRetry()),
      icon: Icon(icon, color: state.status == SyncStatus.error ? c.error : c.onSurfaceVariant),
    );
  }
}
