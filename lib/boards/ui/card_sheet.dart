import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/board_strings.dart';
import '../../l10n/strings.dart';
import '../../state/app_scope.dart';
import '../../ui/common/prediction_bar.dart';
import '../../ui/common/soft.dart';
import '../../ui/tasks/task_tile.dart' show SoftCheck;
import '../board_editor.dart';
import '../boards_controller.dart';
import '../connection.dart';
import '../model/board_item.dart';
import '../model/order.dart';
import 'board_widgets.dart';

/// Opens the card editor sheet (docs/boards/DESIGN.md §9). Commits once when
/// it closes — Tamam, a swipe, a tap on the barrier or back — as a single
/// write of the changed fields, and writes nothing when nothing changed.
///
/// The canvas and Kanban both call this; it is the only place cards are
/// edited.
Future<void> showCardSheet(BuildContext context, OpenBoard board, String cardId) async {
  final editor = board.editor;
  final card = editor.item(cardId);
  if (card == null || card.kind != ItemKind.card || card.deleted) return;
  final view = BoardScope.maybeOf(context)?.view ?? 'kanban';
  final draft = _CardDraft(card, editor.columnOf(cardId))
    ..onClose = () {
      // The connection may have been replaced while the sheet was open.
      board.connection.setActivity(view: view, editing: null);
    };
  final messenger = ScaffoldMessenger.maybeOf(context);
  board.connection.setActivity(view: view, editing: cardId);
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => _CardSheet(board: board, draft: draft, messenger: messenger),
    );
  } finally {
    draft.close(editor);
  }
}

/// The sheet's edits, kept outside its widgets so they can be committed the
/// moment the route pops (its State lives on through the exit animation).
class _CardDraft {
  _CardDraft(BoardItem c, this.shownColumn)
      : id = c.id,
        title = c.title,
        notes = c.notes,
        due = c.due,
        subtasks = c.subtasks,
        colorIndex = c.colorIndex,
        assigneeId = c.assigneeId,
        columnId = shownColumn,
        _title = c.title,
        _notes = c.notes,
        _due = c.due,
        _subtasks = c.subtasks,
        _color = c.colorIndex,
        _assignee = c.assigneeId;

  final String id;

  /// The column the card shows in when the sheet opened.
  final String? shownColumn;

  String title;
  String notes;
  String? due;
  List<CardSubtask> subtasks;
  int colorIndex;
  String? assigneeId;
  String? columnId;

  // As opened: only fields that differ from these are written, so a
  // teammate's edit to another field while the sheet is open survives.
  final String _title;
  final String _notes;
  final String? _due;
  final List<CardSubtask> _subtasks;
  final int _color;
  final String? _assignee;

  bool deleted = false;
  bool _closed = false;
  VoidCallback? onClose;

  bool get closed => _closed;

  Map<String, Object?> changes(BoardEditor e) {
    final ch = <String, Object?>{};
    final t = title.trim();
    if (t.isNotEmpty && t != _title.trim()) ch[F.title] = t;
    if (notes.trim() != _notes.trim()) ch[F.notes] = notes.trim();
    if (due != _due) ch[F.due] = due;
    if (colorIndex != _color) ch[F.colorIndex] = colorIndex;
    if (assigneeId != _assignee) ch[F.assigneeId] = assigneeId;
    if (!_sameSubtasks(subtasks, _subtasks)) ch[F.subtasks] = [for (final s in subtasks) s.toJson()];
    final col = columnId;
    if (col != null && col != shownColumn) {
      final rest = [for (final c in e.cardsIn(col)) if (c.id != id) c];
      ch[F.columnId] = col;
      ch[F.order] = rest.isEmpty ? FractionalOrder.step : FractionalOrder.between(rest.last.order, null);
    }
    return ch;
  }

  static bool _sameSubtasks(List<CardSubtask> a, List<CardSubtask> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].title != b[i].title || a[i].done != b[i].done) return false;
    }
    return true;
  }

  /// Commits (once) and ends the editing presence.
  void close(BoardEditor e) {
    if (_closed) return;
    _closed = true;
    onClose?.call();
    final card = e.item(id);
    if (deleted || card == null || card.deleted || e.readOnly) return;
    final ch = changes(e);
    if (ch.isNotEmpty) e.updateCard(id, ch);
  }
}

class _CardSheet extends StatefulWidget {
  const _CardSheet({required this.board, required this.draft, required this.messenger});

  final OpenBoard board;
  final _CardDraft draft;
  final ScaffoldMessengerState? messenger;

  @override
  State<_CardSheet> createState() => _CardSheetState();
}

class _CardSheetState extends State<_CardSheet> {
  _CardDraft get _d => widget.draft;
  BoardEditor get _e => widget.board.editor;

  late final _title = TextEditingController(text: _d.title);
  late final _notes = TextEditingController(text: _d.notes);
  final _sub = TextEditingController();
  final _titleFocus = FocusNode();
  final _notesFocus = FocusNode();
  final _subFocus = FocusNode();
  final _barKey = GlobalKey<State<PredictionBar>>();

  @override
  void initState() {
    super.initState();
    _title.addListener(() => _d.title = _title.text);
    _notes.addListener(() => _d.notes = _notes.text);
  }

  @override
  void dispose() {
    // Normally committed when the route pops; this covers a route removed
    // without a pop. The tree is locked during dispose, so notify later.
    if (!_d.closed) {
      final e = _e;
      scheduleMicrotask(() => _d.close(e));
    }
    for (final c in [_title, _notes, _sub]) {
      c.dispose();
    }
    for (final f in [_titleFocus, _notesFocus, _subFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = AppScope.of(context).now();
    final current = _d.due == null ? null : DateTime.tryParse(_d.due!);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null && mounted) setState(() => _d.due = dueKey(picked));
  }

  void _addSubtask() {
    final text = _sub.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _d.subtasks = [..._d.subtasks, CardSubtask(id: const Uuid().v4(), title: text)];
      _sub.clear();
    });
    _subFocus.requestFocus();
  }

  void _delete() {
    final s = S.of(context);
    _d.deleted = true;
    _e.deleteItems({_d.id});
    Navigator.pop(context);
    showBoardUndo(widget.messenger, _e, s.deleted, s);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final app = AppScope.of(context);
    final now = app.now();
    final ro = _e.readOnly;
    final shared = _e.doc.isShared;
    final cols = _e.columns;
    final label = t.textTheme.labelLarge?.copyWith(color: c.onSurfaceVariant);
    final due = _d.due == null ? null : DateTime.tryParse(_d.due!);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: PredictionKeys(
              barKey: _barKey,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(s.card, style: t.textTheme.titleLarge)),
                      if (!ro)
                        IconButton(
                          tooltip: s.delete,
                          onPressed: _delete,
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                    ],
                  ),
                  _EditingBanner(board: widget.board, cardId: _d.id),
                  if (cols.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Semantics(
                      label: s.column,
                      container: true,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final col in cols)
                            ChoiceChip(
                              avatar: PastelDot(col.colorIndex),
                              label: Text(col.title.trim().isEmpty ? s.untitled : col.title),
                              selected: _d.columnId == col.id,
                              onSelected: ro ? null : (_) => setState(() => _d.columnId = col.id),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: _title,
                    focusNode: _titleFocus,
                    readOnly: ro,
                    textCapitalization: TextCapitalization.sentences,
                    style: t.textTheme.titleMedium,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(hintText: s.cardTitleHint),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _notes,
                    focusNode: _notesFocus,
                    readOnly: ro,
                    minLines: 2,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(hintText: s.description, prefixIcon: const Icon(Icons.notes_rounded)),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SoftChip(
                        label: due == null ? s.cardDue : '${s.cardDue}: ${dueLabel(s, due, now)}',
                        icon: Icons.calendar_month_rounded,
                        selected: due != null,
                        onTap: ro ? null : _pickDue,
                      ),
                      if (due != null && !ro)
                        SoftChip(label: s.noDue, icon: Icons.close_rounded, onTap: () => setState(() => _d.due = null)),
                    ],
                  ),
                  if (shared) ...[
                    const SizedBox(height: 16),
                    Text(s.assignee, style: label),
                    const SizedBox(height: 8),
                    _AssigneeChooser(
                      board: widget.board,
                      selected: _d.assigneeId,
                      selfId: app.boards.currentAccount()?.userId,
                      enabled: !ro,
                      onChanged: (id) => setState(() => _d.assigneeId = id),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(s.color, style: label),
                  const SizedBox(height: 8),
                  IgnorePointer(
                    ignoring: ro,
                    child: PastelPicker(selected: _d.colorIndex, onChanged: (i) => setState(() => _d.colorIndex = i)),
                  ),
                  const SizedBox(height: 16),
                  Text(s.subtasks, style: label),
                  for (final st in _d.subtasks)
                    Row(
                      children: [
                        SoftCheck(
                          done: st.done,
                          size: 22,
                          colorIndex: _d.colorIndex,
                          onTap: ro
                              ? () {}
                              : () => setState(() => _d.subtasks = [
                                    for (final x in _d.subtasks) x.id == st.id ? x.copyWith(done: !x.done) : x,
                                  ]),
                        ),
                        Expanded(
                          child: Text(
                            st.title,
                            style: TextStyle(
                              decoration: st.done ? TextDecoration.lineThrough : null,
                              color: st.done ? c.onSurfaceVariant : null,
                            ),
                          ),
                        ),
                        if (!ro)
                          IconButton(
                            tooltip: s.delete,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () => setState(() => _d.subtasks = [
                                  for (final x in _d.subtasks)
                                    if (x.id != st.id) x,
                                ]),
                          ),
                      ],
                    ),
                  if (!ro) ...[
                    const SizedBox(height: 6),
                    TextField(
                      controller: _sub,
                      focusNode: _subFocus,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(hintText: s.addSubtask, prefixIcon: const Icon(Icons.add_rounded)),
                      onSubmitted: (_) => _addSubtask(),
                    ),
                  ],
                  if (shared) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(Icons.cloud_outlined, size: 16, color: c.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(s.savedOnClose, style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(onPressed: () => Navigator.pop(context), child: Text(s.done)),
                ],
              ),
            ),
          ),
          PredictionBar(
            key: _barKey,
            fields: [
              PredictiveField(_title, _titleFocus),
              PredictiveField(_notes, _notesFocus),
              PredictiveField(_sub, _subFocus),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Şu an düzenleyen: Ayşe" while a teammate has the same card open. Names
/// stand alone after the colon (no Turkish suffix on user content).
class _EditingBanner extends StatelessWidget {
  const _EditingBanner({required this.board, required this.cardId});

  final OpenBoard board;
  final String cardId;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    return ValueListenableBuilder<List<Peer>>(
      valueListenable: board.connection.peers,
      builder: (context, peers, _) {
        final names = {for (final p in peers) if (p.editing == cardId) p.name}.toList();
        if (names.isEmpty) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(top: 4, bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: t.colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(Icons.edit_note_rounded, color: t.colorScheme.onTertiaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.editingNow(names.join(', ')),
                  style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onTertiaryContainer),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Members are not stored on the device, so the choice is the people here
/// now, yourself, and whoever the card is already assigned to.
class _AssigneeChooser extends StatelessWidget {
  const _AssigneeChooser({
    required this.board,
    required this.selected,
    required this.selfId,
    required this.enabled,
    required this.onChanged,
  });

  final OpenBoard board;
  final String? selected;
  final String? selfId;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ValueListenableBuilder<List<Peer>>(
      valueListenable: board.connection.peers,
      builder: (context, peers, _) {
        final people = <(String?, String, String?, int)>[(null, s.unassigned, null, 0)];
        final seen = <String>{};
        for (final p in peers) {
          if (p.userId == selfId || !seen.add(p.userId)) continue;
          people.add((p.userId, p.name, p.name, p.colorIndex));
        }
        if (selfId != null) people.add((selfId, s.me, null, 3));
        final sel = selected;
        if (sel != null && !people.any((x) => x.$1 == sel)) people.add((sel, s.someone, null, 0));
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (id, label, avatar, color) in people)
              ChoiceChip(
                avatar: id == null
                    ? const Icon(Icons.person_off_outlined, size: 18)
                    : PersonAvatar(name: avatar, colorIndex: color, size: 22),
                label: Text(label),
                selected: selected == id,
                onSelected: enabled ? (_) => onChanged(id) : null,
              ),
          ],
        );
      },
    );
  }
}
