import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../ui/common/soft.dart';
import '../boards_controller.dart';
import '../boards_repository.dart';
import '../connection.dart';
import 'canvas_strings.dart';
import 'ink_layer.dart';
import 'input.dart';
import 'item_painter.dart';
import 'painters.dart';
import 'presence.dart';
import 'retained_picture.dart';
import 'selection_toolbar.dart';
import 'session.dart';
import 'sticky_editor.dart';
import 'toolbar.dart';

/// The infinite canvas of a board (docs/boards/DESIGN.md §8).
///
/// Everything on the board is painted (no item widgets) from a scene derived
/// from the editor; one Listener feeds every pointer event into
/// [BoardInput]. The page around it owns the Scaffold (with
/// `resizeToAvoidBottomInset: false`) and the back button.
///
/// [viewState]'s `offset` is the canvas point at the centre of the view, so
/// a restored view survives window resizes and rotation.
class BoardCanvasView extends StatefulWidget {
  const BoardCanvasView({
    super.key,
    required this.board,
    required this.viewState,
    required this.onViewChanged,
    required this.onOpenCard,
    required this.stylusOnly,
    this.onStylusDetected,
  });

  final OpenBoard board;

  /// This device's last viewport for the board, if any.
  final BoardViewState? viewState;

  /// Called (throttled) when the viewport settles; the page saves it.
  final ValueChanged<BoardViewState> onViewChanged;

  /// A card was double-tapped: open the card sheet.
  final void Function(String cardId) onOpenCard;

  /// Palm rejection: only the stylus draws.
  final bool stylusOnly;

  /// First stylus contact (turns stylusOnly on when the setting allows).
  final VoidCallback? onStylusDetected;

  /// Width from which the canvas edits in place and shows the side toolbar.
  static const wideFrom = 600.0;

  @override
  State<BoardCanvasView> createState() => _BoardCanvasViewState();
}

/// For tests: the live session behind a canvas.
@visibleForTesting
BoardSession debugCanvasSession(State<BoardCanvasView> state) => (state as _BoardCanvasViewState)._session;

class _BoardCanvasViewState extends State<BoardCanvasView> with TickerProviderStateMixin implements BoardCanvasHost {
  BoardSession? _sessionOrNull;
  late BoardInput _input;

  BoardSession get _session => _sessionOrNull!;
  S _s = S.tr;
  bool _wide = true;
  EdgeInsets _chrome = EdgeInsets.zero;
  bool _placed = false;
  Timer? _viewTimer;
  bool _viewDirty = false;
  BoardPalette? _palette;

  static const _viewDebounce = Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();
    if (kIsWeb) unawaited(BrowserContextMenu.disableContextMenu());
  }

  /// Starts once the theme and language are known, so card titles are
  /// measured once, in the colour they are drawn in.
  void _start(BoardPalette p) {
    _sessionOrNull = BoardSession(board: widget.board, vsync: this, host: this, textColor: p.text, mutedColor: p.muted);
    _input = BoardInput(_session);
    _session.viewport.addListener(_onViewport);
    _placed = false;
    widget.board.connection.setActivity(view: 'canvas');
  }

  void _stop() {
    _session.commitEdit?.call();
    _saveView();
    _session.connection.sendCursor(null);
    _session.viewport.removeListener(_onViewport);
    _input.dispose();
    _session.dispose();
  }

  @override
  void didUpdateWidget(BoardCanvasView old) {
    super.didUpdateWidget(old);
    if (!identical(old.board, widget.board)) {
      _stop();
      _start(_palette!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _s = S.of(context);
    final p = BoardPalette.of(Theme.of(context));
    if (_sessionOrNull == null) {
      _palette = p;
      _start(p);
    }
    _session.reduceMotion = MediaQuery.disableAnimationsOf(context);
    final scene = _session.scene;
    if (p != _palette || scene.placeholder != _s.untitled) {
      // Theme or language switch: re-measure in the new colours (rare).
      _palette = p;
      scene
        ..textColor = p.text
        ..mutedColor = p.muted
        ..placeholder = _s.untitled
        ..rebuild();
    }
  }

  @override
  void dispose() {
    _viewTimer?.cancel();
    if (_sessionOrNull != null) _stop();
    if (kIsWeb) unawaited(BrowserContextMenu.enableContextMenu());
    super.dispose();
  }

  // ------------------------------------------------------- view memory

  void _onViewport() {
    if (!_placed) return;
    _viewDirty = true;
    _viewTimer?.cancel();
    _viewTimer = Timer(_viewDebounce, _saveView);
  }

  void _saveView() {
    _viewTimer?.cancel();
    if (!_viewDirty) return;
    _viewDirty = false;
    final vp = _session.viewport;
    if (vp.size.isEmpty) return;
    widget.onViewChanged(BoardViewState(view: 'canvas', offset: vp.canvasCenter, scale: vp.scale, fitted: true));
  }

  /// First layout: restore this device's view, or zoom to fit once.
  void _place() {
    final vs = widget.viewState;
    final vp = _session.viewport;
    // Let the minimum zoom follow the board even when restoring.
    _session.updateMinScale();
    if (vs != null && vs.fitted) {
      vp.centerOn(vs.offset, vs.scale);
    } else {
      _session.fitToScreen(animate: false);
      _viewDirty = true;
      _viewTimer = Timer(_viewDebounce, _saveView);
    }
    _placed = true;
  }

  // ------------------------------------------------------------- host

  @override
  bool get inlineEditing => _wide;

  @override
  bool get stylusOnly => widget.stylusOnly;

  @override
  EdgeInsets get chromeInsets => _chrome;

  @override
  S get strings => _s;

  @override
  Future<String?> editStickyInSheet(String stickyId, String text) {
    final color = _session.scene.byId(stickyId)?.item.colorIndex ?? 5;
    return showStickySheet(context, text: text, colorIndex: color);
  }

  @override
  void openCard(String cardId) => widget.onOpenCard(cardId);

  @override
  void showSnack(String text, {VoidCallback? undo}) {
    final m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    if (undo != null) {
      showUndoSnack(m, text, undo, _s.undo);
    } else {
      m
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  void showItemMenu(Offset screen) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    unawaited(showSelectionMenu(context, _session, box.localToGlobal(screen)));
  }

  @override
  void renameColumn(String columnId) => unawaited(_renameColumn(columnId));

  Future<void> _renameColumn(String columnId) async {
    final col = _session.editor.item(columnId);
    if (col == null) return;
    final c = TextEditingController(text: col.title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_s.canvasRename),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: _s.canvasColumnName),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(_s.save)),
        ],
      ),
    );
    // The dialog's field may still be animating out; dispose after it.
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    final t = name?.trim();
    if (t != null && t.isNotEmpty && mounted) _session.editor.updateColumn(columnId, title: t);
  }

  @override
  void stylusDetected() => widget.onStylusDetected?.call();

  @override
  void viewChanged() => _onViewport();

  // -------------------------------------------------------- shortcuts

  bool get _canEdit => !_session.isEditing && !_session.readOnly;

  Map<ShortcutActivator, Intent> get _shortcuts {
    final map = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.keyV): const _ToolIntent(BoardTool.select),
      const SingleActivator(LogicalKeyboardKey.keyP): const _ToolIntent(BoardTool.pen),
      const SingleActivator(LogicalKeyboardKey.keyF): const _ToolIntent(BoardTool.highlighter),
      const SingleActivator(LogicalKeyboardKey.keyE): const _ToolIntent(BoardTool.eraser),
      const SingleActivator(LogicalKeyboardKey.keyN): const _NewStickyIntent(),
      const SingleActivator(LogicalKeyboardKey.keyK): const _NewCardIntent(),
      const SingleActivator(LogicalKeyboardKey.digit1, shift: true): const _FitIntent(),
      const CharacterActivator('!'): const _FitIntent(),
      const SingleActivator(LogicalKeyboardKey.delete): const _DeleteIntent(),
      const SingleActivator(LogicalKeyboardKey.backspace): const _DeleteIntent(),
      const SingleActivator(LogicalKeyboardKey.escape): const _EscapeIntent(),
    };
    for (final cmd in [(control: true, meta: false), (control: false, meta: true)]) {
      SingleActivator k(LogicalKeyboardKey key, {bool shift = false}) =>
          SingleActivator(key, control: cmd.control, meta: cmd.meta, shift: shift);
      map[k(LogicalKeyboardKey.equal)] = const _ZoomIntent(1.25);
      map[k(LogicalKeyboardKey.equal, shift: true)] = const _ZoomIntent(1.25);
      map[k(LogicalKeyboardKey.numpadAdd)] = const _ZoomIntent(1.25);
      map[k(LogicalKeyboardKey.minus)] = const _ZoomIntent(1 / 1.25);
      map[k(LogicalKeyboardKey.numpadSubtract)] = const _ZoomIntent(1 / 1.25);
      map[CharacterActivator('+', control: cmd.control, meta: cmd.meta)] = const _ZoomIntent(1.25);
      map[k(LogicalKeyboardKey.keyD)] = const _DuplicateIntent();
      map[k(LogicalKeyboardKey.keyZ)] = const _UndoIntent();
      map[k(LogicalKeyboardKey.keyZ, shift: true)] = const _RedoIntent();
      map[k(LogicalKeyboardKey.keyY)] = const _RedoIntent();
    }
    return map;
  }

  /// Every action is disabled while a sticky is being edited, so its keys
  /// (letters, Backspace, ⌘Z) reach the text field instead.
  Map<Type, Action<Intent>> get _actions => {
    _ToolIntent: _BoardAction<_ToolIntent>(() => _canEdit, (i) => _session.setTool(i.tool)),
    _NewStickyIntent: _BoardAction<_NewStickyIntent>(() => _canEdit, (_) => _session.addStickyAtCenter()),
    _NewCardIntent: _BoardAction<_NewCardIntent>(
      () => _canEdit && _session.firstOpenColumn != null,
      (_) => _session.addCard(),
    ),
    _FitIntent: _BoardAction<_FitIntent>(() => !_session.isEditing, (_) => _session.fitToScreen()),
    _ZoomIntent: _BoardAction<_ZoomIntent>(() => !_session.isEditing, (i) => _session.zoomBy(i.factor)),
    _DeleteIntent: _BoardAction<_DeleteIntent>(
      () => _canEdit && _session.selection.value.isNotEmpty,
      (_) => _session.deleteSelection(),
    ),
    _DuplicateIntent: _BoardAction<_DuplicateIntent>(
      () => _canEdit && _session.freeOf(_session.selection.value).isNotEmpty,
      (_) => _session.duplicateSelection(),
    ),
    _UndoIntent: _BoardAction<_UndoIntent>(() => _canEdit && _session.editor.canUndo, (_) => _session.undo()),
    _RedoIntent: _BoardAction<_RedoIntent>(() => _canEdit && _session.editor.canRedo, (_) => _session.redo()),
    _EscapeIntent: _BoardAction<_EscapeIntent>(
      () => !_session.isEditing && (_session.selection.value.isNotEmpty || _session.tool.value != BoardTool.select),
      (_) {
        _session.clearSelection();
        _session.setTool(BoardTool.select);
      },
    ),
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e.logicalKey != LogicalKeyboardKey.space || _session.isEditing) return KeyEventResult.ignored;
    if (e is KeyDownEvent || e is KeyRepeatEvent) {
      _input.spaceHeld = true;
      return KeyEventResult.handled;
    }
    if (e is KeyUpEvent) {
      _input.spaceHeld = false;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ------------------------------------------------------------ build

  EdgeInsets _chromeFor(Size size, EdgeInsets safe) => _wide
      ? EdgeInsets.fromLTRB(safe.left + 76, safe.top, safe.right, safe.bottom + 8)
      : EdgeInsets.fromLTRB(safe.left, safe.top, safe.right, safe.bottom + 76);

  @override
  Widget build(BuildContext context) {
    final palette = _palette ?? BoardPalette.of(Theme.of(context));
    // viewPadding: unlike padding it doesn't change while a keyboard opens,
    // so the canvas doesn't rebuild through the keyboard animation.
    final safe = MediaQuery.viewPaddingOf(context);
    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: _actions,
        child: Focus(
          focusNode: _session.keyboardFocus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: LayoutBuilder(
            builder: (context, cons) {
              final size = cons.biggest;
              _wide = size.width >= BoardCanvasView.wideFrom;
              _chrome = _chromeFor(size, safe);
              final vp = _session.viewport;
              if (size != vp.size) {
                // Layout time: update silently, painters read it this frame,
                // everyone else hears about it after the frame.
                vp.silently(() {
                  vp.setSize(size);
                  if (!_placed) _place();
                });
                SchedulerBinding.instance.addPostFrameCallback((_) {
                  if (mounted) vp.flush();
                });
              }
              return _canvas(context, palette, safe);
            },
          ),
        ),
      ),
    );
  }

  Widget _canvas(BuildContext context, BoardPalette palette, EdgeInsets safe) {
    final session = _session;
    final s = _s;
    final assignee = _assigneeLook;
    final painted = Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: CustomPaint(painter: GridPainter(session.viewport, palette.grid))),
        RepaintBoundary(
          child: CustomPaint(
            painter: BoardWorldPainter(session, palette, s, assignee: assignee),
            isComplex: true,
            willChange: true,
          ),
        ),
        RetainedPicture(source: BoardOverviewSource(session, palette, s, assignee: assignee)),
        RetainedPicture(source: LiftedSource(session, palette, s, assignee: assignee)),
        RepaintBoundary(child: CustomPaint(painter: BoardActiveStrokePainter(session.activeInk, session.viewport))),
        RepaintBoundary(child: CustomPaint(painter: OverlayPainter(session, palette, s, session.peers))),
        RepaintBoundary(
          child: CustomPaint(painter: PresencePainter(session.presence, session.viewport, palette, session.text)),
        ),
      ],
    );
    final input = RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        // Wins every arena at once: no outer scrollable, page swipe or the
        // Cupertino back-swipe strip can take a canvas gesture.
        CanvasClaimRecognizer: GestureRecognizerFactoryWithHandlers<CanvasClaimRecognizer>(
          CanvasClaimRecognizer.new,
          (_) {},
        ),
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _input.down,
        onPointerMove: _input.move,
        onPointerUp: _input.up,
        onPointerCancel: _input.cancel,
        onPointerHover: _input.hover,
        onPointerSignal: _input.signal,
        onPointerPanZoomStart: _input.panZoomStart,
        onPointerPanZoomUpdate: _input.panZoomUpdate,
        onPointerPanZoomEnd: _input.panZoomEnd,
        child: painted,
      ),
    );
    final region = ValueListenableBuilder<MouseCursor>(
      valueListenable: session.cursor,
      builder: (context, cursor, child) => MouseRegion(cursor: cursor, onExit: _input.exit, child: child),
      child: input,
    );
    return Listener(
      // Sees every pointer (toolbars too) without taking part: for the
      // touch/pointer choice when an edit zooms in.
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => session.lastTouch = e.kind == PointerDeviceKind.touch,
      child: ColoredBox(
        color: palette.background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: session.itemCount,
              builder: (context, n, child) => Semantics(
                container: true,
                label: s.canvasSummary(n),
                child: ExcludeSemantics(child: child),
              ),
              child: region,
            ),
            ListenableBuilder(
              listenable: Listenable.merge([session.itemCount, session.columnCount]),
              builder: (context, _) => session.itemCount.value > 0 || session.columnCount.value > 0 || session.readOnly
                  ? const SizedBox.shrink()
                  : IgnorePointer(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            s.canvasEmpty,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                    ),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: session.editing,
              builder: (context, id, _) => id == null || !_wide
                  ? const SizedBox.shrink()
                  : InlineStickyEditor(key: ValueKey(id), session: session, id: id, palette: palette),
            ),
            SelectionToolbar(session: session),
            if (_wide) ...[
              Positioned(
                left: safe.left + 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: RepaintBoundary(child: WideToolbar(session: session)),
                ),
              ),
              Positioned(
                right: safe.right + 16,
                bottom: safe.bottom + 16,
                child: RepaintBoundary(child: ZoomControls(session: session)),
              ),
            ] else
              Positioned(
                left: 12,
                right: 12,
                bottom: safe.bottom + 12,
                child: Center(
                  child: RepaintBoundary(child: PhoneToolbar(session: session)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Initials and colour of an assignee who is on the board right now.
  (String, int)? _assigneeLook(String userId) {
    for (final Peer p in _session.peers.value) {
      if (p.userId == userId) return (initialsOf(p.name), p.colorIndex);
    }
    return null;
  }
}

/// Claims every pointer at once, like [EagerGestureRecognizer], and also
/// trackpad pan/zoom pointers, so two-finger trackpad scrolls never reach
/// an outer scrollable either.
class CanvasClaimRecognizer extends EagerGestureRecognizer {
  CanvasClaimRecognizer();

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    resolvePointer(event.pointer, GestureDisposition.accepted);
    stopTrackingPointer(event.pointer);
  }

  @override
  String get debugDescription => 'board canvas';
}

class _ToolIntent extends Intent {
  const _ToolIntent(this.tool);

  final BoardTool tool;
}

class _NewStickyIntent extends Intent {
  const _NewStickyIntent();
}

class _NewCardIntent extends Intent {
  const _NewCardIntent();
}

class _FitIntent extends Intent {
  const _FitIntent();
}

class _ZoomIntent extends Intent {
  const _ZoomIntent(this.factor);

  final double factor;
}

class _DeleteIntent extends Intent {
  const _DeleteIntent();
}

class _DuplicateIntent extends Intent {
  const _DuplicateIntent();
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

class _EscapeIntent extends Intent {
  const _EscapeIntent();
}

/// An action that reports itself disabled (so the key passes on to the
/// focused text field) whenever [enabled] says so.
class _BoardAction<T extends Intent> extends Action<T> {
  _BoardAction(this.enabled, this.run);

  final bool Function() enabled;
  final void Function(T intent) run;

  @override
  bool isEnabled(T intent) => enabled();

  @override
  Object? invoke(T intent) {
    run(intent);
    return null;
  }
}
