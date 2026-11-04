import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/turkish_text.dart' as tt;
import '../../l10n/board_strings.dart';
import '../../l10n/strings.dart';
import '../../theme/pamnot_theme.dart';
import '../../ui/common/soft.dart';
import '../board_editor.dart';
import '../boards_controller.dart';
import '../connection.dart';

/// The open board and the view it shows, for widgets below the board page
/// (the card sheet reports the view in presence).
class BoardScope extends InheritedWidget {
  const BoardScope({super.key, required this.board, required this.view, required super.child});

  final OpenBoard board;

  /// 'canvas' or 'kanban'.
  final String view;

  static BoardScope? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<BoardScope>();

  @override
  bool updateShouldNotify(BoardScope old) => old.board != board || old.view != view;
}

/// Rebuilds only when [select] of the editor changes, so a title in the top
/// bar does not rebuild on every card move.
class EditorSelector<T> extends StatefulWidget {
  const EditorSelector({super.key, required this.editor, required this.select, required this.builder});

  final BoardEditor editor;
  final T Function(BoardEditor e) select;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<EditorSelector<T>> createState() => _EditorSelectorState<T>();
}

class _EditorSelectorState<T> extends State<EditorSelector<T>> {
  late T _value = widget.select(widget.editor);

  @override
  void initState() {
    super.initState();
    widget.editor.addListener(_changed);
  }

  @override
  void didUpdateWidget(EditorSelector<T> old) {
    super.didUpdateWidget(old);
    if (old.editor != widget.editor) {
      old.editor.removeListener(_changed);
      widget.editor.addListener(_changed);
    }
    _value = widget.select(widget.editor);
  }

  @override
  void dispose() {
    widget.editor.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final v = widget.select(widget.editor);
    if (v != _value) setState(() => _value = v);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}

/// Up to two initials, Turkish-aware ("ilker" → "İ").
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  final first = words.first.characters.first;
  final second = words.length > 1 ? words.last.characters.first : '';
  return tt.upper('$first$second', turkish: true);
}

/// A round avatar with initials on the person's pastel, ringed in its accent.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, this.name, required this.colorIndex, this.size = 28});

  /// Null when the person is not known on this device (a person icon).
  final String? name;
  final int colorIndex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = pastelAt(colorIndex);
    final n = name;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.paper(t.brightness),
        shape: BoxShape.circle,
        border: Border.all(color: p.accent, width: size >= 26 ? 2 : 1.5),
      ),
      child: n == null
          ? Icon(Icons.person_rounded, size: size * 0.6, color: t.colorScheme.onSurfaceVariant)
          : Text(
              initialsOf(n),
              maxLines: 1,
              textScaler: TextScaler.noScaling,
              style: t.textTheme.labelSmall?.copyWith(
                fontSize: size * 0.38,
                fontWeight: FontWeight.w800,
                color: t.colorScheme.onSurface,
              ),
            ),
    );
  }
}

/// Others on the board: overlapping avatars, at most [max] plus '+n'.
class PeerAvatars extends StatelessWidget {
  const PeerAvatars({super.key, required this.peers, this.max = 3, this.onTap});

  final List<Peer> peers;
  final int max;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (peers.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context);
    const size = 28.0, step = 18.0;
    final shown = peers.take(max).toList();
    final extra = peers.length - shown.length;
    final count = shown.length + (extra > 0 ? 1 : 0);
    return Semantics(
      button: onTap != null,
      label: peers.map((p) => p.name).join(', '),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: SizedBox(
            width: size + step * (count - 1),
            height: size,
            child: ExcludeSemantics(
              child: Stack(
                children: [
                  for (var i = 0; i < shown.length; i++)
                    Positioned(left: i * step, child: PersonAvatar(name: shown[i].name, colorIndex: shown[i].colorIndex)),
                  if (extra > 0)
                    Positioned(
                      left: shown.length * step,
                      child: Container(
                        width: size,
                        height: size,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.colorScheme.surfaceContainerHighest,
                          shape: BoxShape.circle,
                          border: Border.all(color: t.colorScheme.outline, width: 2),
                        ),
                        child: Text('+$extra',
                            textScaler: TextScaler.noScaling,
                            style: t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-field dialog (rename board or column). Returns the trimmed text,
/// or null when cancelled or left empty.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  String? action,
}) async {
  final out = await showDialog<String>(
    context: context,
    builder: (_) => _PromptDialog(title: title, initial: initial, hint: hint, action: action),
  );
  final v = out?.trim();
  return v == null || v.isEmpty ? null : v;
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({required this.title, required this.initial, this.hint, this.action});

  final String title;
  final String initial;
  final String? hint;
  final String? action;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _c = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: Text(widget.action ?? s.save)),
      ],
    );
  }
}

/// A sheet with the pastel swatches; returns the chosen index.
Future<int?> pickPastel(BuildContext context, {required int selected}) {
  final s = S.of(context);
  return showModalBottomSheet<int>(
    context: context,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.color, style: Theme.of(sheet).textTheme.titleLarge),
            const SizedBox(height: 16),
            PastelPicker(selected: selected, onChanged: (i) => Navigator.pop(sheet, i)),
          ],
        ),
      ),
    ),
  );
}

/// "şimdi", "5 dk önce", "2 sa önce", "dün", "3 gün önce", then a date.
String relativeAgo(S s, DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return s.justNow;
  if (d.inMinutes < 60) return s.minutesAgo(d.inMinutes);
  if (d.inHours < 24) return s.hoursAgo(d.inHours);
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  if (days <= 1) return s.yesterdayAgo;
  if (days < 7) return s.daysAgo(days);
  return _format(s, t.year == now.year ? 'd MMM' : 'd MMM y', t);
}

/// A card's due date: "12 Kas", or "12 Kas 2027" in another year.
String dueLabel(S s, DateTime due, DateTime now) => _format(s, due.year == now.year ? 'd MMM' : 'd MMM y', due);

final Map<String, DateFormat> _formats = {};

/// DateFormat parses its pattern on creation; card faces reuse one per
/// locale and pattern.
String _format(S s, String pattern, DateTime d) =>
    _formats.putIfAbsent('${s.locale}|$pattern', () => DateFormat(pattern, s.locale)).format(d);

/// An undo snack for one board edit. [token] is the editor's undo token
/// right after the edit; a later edit makes the snack do nothing rather
/// than revert the wrong thing.
void showBoardUndo(ScaffoldMessengerState? messenger, BoardEditor editor, String text, S s) {
  if (messenger == null) return;
  final token = editor.undoToken;
  if (token == null) return;
  showUndoSnack(messenger, text, () {
    if (!identical(editor.undoToken, token)) return;
    final out = editor.undo();
    if (out.skipped) {
      messenger.showSnackBar(SnackBar(content: Text(s.changedBySomeoneElse)));
    }
  }, s.undo);
}
