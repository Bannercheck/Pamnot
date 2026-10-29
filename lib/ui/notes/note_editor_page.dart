import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../models/ink.dart';
import '../../models/note.dart';
import '../../models/settings.dart';
import '../../services/handwriting.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../../theme/pamnot_theme.dart';
import '../common/prediction_bar.dart';
import '../common/soft.dart';
import 'ink/ink_canvas.dart';
import 'ink/ink_controller.dart';
import 'ink/ink_lines.dart';
import 'ink/ink_toolbar.dart';

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({super.key, required this.note, this.startInInk = false});

  final Note note;
  final bool startInInk;

  static Future<void> open(BuildContext context, Note note, {bool ink = false}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => NoteEditorPage(note: note, startInInk: ink)));

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final AppController _app = AppScope.of(context);
  late Note _note = widget.note;
  late final _title = TextEditingController(text: widget.note.title);
  late final _body = TextEditingController(text: widget.note.body);
  final _titleFocus = FocusNode();
  final _bodyFocus = FocusNode();
  final _barKey = GlobalKey<State<PredictionBar>>();
  InkController _ink = InkController(const []);
  late bool _inkMode = widget.startInInk || (widget.note.hasInk && widget.note.body.isEmpty);
  bool _inkLoaded = false;
  bool _converting = false;
  int _savedInkRevision = 0;
  bool _dirty = false;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _title.addListener(_changed);
    _body.addListener(_changed);
    _app.ensureInk(_note.id).then((_) {
      if (!mounted) return;
      final fresh = _app.noteById(_note.id);
      final placeholder = _ink;
      setState(() {
        _ink = InkController(fresh?.ink ?? _note.ink)..addListener(_inkChanged);
        _inkLoaded = true;
      });
      placeholder.dispose();
    });
    if (!_inkMode && widget.note.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bodyFocus.requestFocus());
    }
  }

  void _changed() {
    if (_title.text == _note.title && _body.text == _note.body) return;
    _dirty = true;
    _scheduleSave();
  }

  void _inkChanged() {
    if (_ink.revision == _savedInkRevision) return;
    _dirty = true;
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _commit);
  }

  /// Hands the edited note to the controller (which saves it after a pause).
  void _commit() {
    _saveTimer?.cancel();
    if (!_dirty) return;
    final inkChanged = _ink.revision != _savedInkRevision;
    final next = _note.copyWith(
      title: _title.text,
      body: _body.text,
      ink: _inkLoaded ? _ink.strokes : _note.ink,
      updatedAt: _app.now(),
    );
    _dirty = false;
    _savedInkRevision = _ink.revision;
    _note = next;
    final exists = _app.noteById(next.id) != null;
    if (next.isEmpty && !exists) return;
    _app.upsertNote(next, inkChanged: inkChanged && _inkLoaded);
  }

  void _finish() {
    _commit();
    if (_note.isEmpty && _app.noteById(_note.id) != null) _app.deleteNote(_note.id);
  }

  @override
  void dispose() {
    // Normally saved on pop; this covers routes removed without one. The
    // tree is locked during dispose, so notify on the next microtask.
    if (_dirty) scheduleMicrotask(_finish);
    _saveTimer?.cancel();
    _title.dispose();
    _body.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    _ink.dispose();
    super.dispose();
  }

  void _update(Note n) {
    setState(() => _note = n);
    _dirty = true;
    _commit();
  }

  void _onStylus() {
    final s = _app.settings;
    if (s.autoStylusOnly && !s.stylusOnly) {
      _app.updateSettings(s.copyWith(stylusOnly: true));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).stylusOnlyOn)));
    }
  }

  Future<void> _convert() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final rec = _app.handwriting;
    final lang = switch (_app.settings.predictionLanguage) {
      PredictionLanguage.tr => 'tr',
      PredictionLanguage.en => 'en',
      PredictionLanguage.auto => _app.writingLanguage,
    };
    final model = HandwritingRecognizer.modelFor(lang);
    final strokes = _ink.strokes;
    final lines = segmentLines(strokes);
    if (lines.isEmpty) return;
    setState(() => _converting = true);
    try {
      if (!await rec.isModelReady(model)) {
        messenger.showSnackBar(SnackBar(content: Text(s.downloadingModel)));
        if (!await rec.prepare(model)) {
          messenger.showSnackBar(SnackBar(content: Text(s.recognitionFailed)));
          return;
        }
      }
      final best = <String>[];
      var alternatives = <String>[];
      for (final line in lines) {
        final c = await rec.recognize(line, model: model, preContext: best.join(' '));
        if (c.isEmpty) continue;
        best.add(c.first);
        if (lines.length == 1) alternatives = c.take(4).toList();
      }
      if (best.isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(s.recognitionFailed)));
        return;
      }
      final options = lines.length == 1 ? alternatives : [best.join('\n')];
      if (!mounted) return;
      final picked = await _pickRecognition(options);
      if (picked == null) return;
      final (text, removeInk) = picked;
      final body = _body.text;
      final sep = body.isEmpty || body.endsWith('\n') ? '' : '\n';
      _body.text = '$body$sep$text';
      if (removeInk) _ink.removeStrokes({for (final l in lines) ...l});
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  Future<(String, bool)?> _pickRecognition(List<String> options) {
    final s = S.of(context);
    var removeInk = true;
    return showModalBottomSheet<(String, bool)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.pickRecognition, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                for (final o in options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SoftCard(
                      shadow: false,
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      onTap: () => Navigator.pop(context, (o, removeInk)),
                      child: Text(o, style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.removeInkAfter),
                  value: removeInk,
                  onChanged: (v) => setSheet(() => removeInk = v),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickColor() async {
    final s = S.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.color, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              PastelPicker(
                selected: _note.colorIndex,
                onChanged: (i) {
                  _update(_note.copyWith(colorIndex: i));
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _delete() {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    _commit();
    final removed = _app.deleteNote(_note.id);
    _dirty = false;
    Navigator.of(context).pop();
    if (removed != null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(s.deleted),
        action: SnackBarAction(label: s.undo, onPressed: () => _app.restoreNote(removed)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context, {Slice.settings});
    final s = S.of(context);
    final t = Theme.of(context);
    final paper = pastelAt(_note.colorIndex).paper(t.brightness);
    // On wide screens the page floats on a neutral desk so its edges show.
    final desk = _inkMode && MediaQuery.sizeOf(context).width > 700 ? t.colorScheme.surfaceContainer : paper;
    final converter = app.handwriting.isSupported ? _convert : null;

    final titleField = TextField(
      controller: _title,
      focusNode: _titleFocus,
      textCapitalization: TextCapitalization.sentences,
      style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        hintText: s.title,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      ),
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => _inkMode ? null : _bodyFocus.requestFocus(),
    );

    final Widget content;
    if (_inkMode) {
      content = !_inkLoaded
          ? const Center(child: CircularProgressIndicator())
          : CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _ink.undo,
                const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _ink.undo,
                const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): _ink.redo,
                const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _ink.redo,
              },
              child: Focus(
                autofocus: true,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: InkCanvas(
                        controller: _ink,
                        paper: _note.paper,
                        paperColor: paper,
                        stylusOnly: app.settings.stylusOnly,
                        onStylusDetected: _onStylus,
                        bottomInset: 96,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SafeArea(
                        top: false,
                        child: Center(
                          child: InkToolbar(controller: _ink, onConvert: converter, converting: _converting),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
    } else {
      content = Column(
        children: [
          Expanded(
            child: ContentWidth(
              maxWidth: 760,
              child: PredictionKeys(
                barKey: _barKey,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 40),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    titleField,
                    TextField(
                      controller: _body,
                      focusNode: _bodyFocus,
                      maxLines: null,
                      minLines: 12,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      style: t.textTheme.bodyLarge?.copyWith(height: 1.55, fontSize: 17),
                      decoration: InputDecoration(
                        hintText: s.startWriting,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          PredictionBar(
            key: _barKey,
            fields: [PredictiveField(_title, _titleFocus), PredictiveField(_body, _bodyFocus)],
          ),
        ],
      );
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _finish();
      },
      child: Scaffold(
        backgroundColor: desk,
        appBar: AppBar(
          backgroundColor: desk,
          title: _inkMode
              ? SizedBox(width: 420, child: titleField)
              : null,
          titleSpacing: 0,
          actions: [
            _ModeToggle(
              ink: _inkMode,
              onChanged: (v) {
                FocusScope.of(context).unfocus();
                setState(() => _inkMode = v);
              },
            ),
            IconButton(
              tooltip: _note.pinned ? s.unpin : s.pin,
              onPressed: () => _update(_note.copyWith(pinned: !_note.pinned)),
              icon: Icon(_note.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined),
            ),
            IconButton(tooltip: s.color, onPressed: _pickColor, icon: const Icon(Icons.palette_outlined)),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (v) {
                switch (v) {
                  case 'delete':
                    _delete();
                  case 'clear':
                    _ink.clear();
                  default:
                    final p = PaperStyle.values.firstWhere((p) => p.name == v);
                    _update(_note.copyWith(paper: p));
                }
              },
              itemBuilder: (_) => [
                for (final (p, label) in [
                  (PaperStyle.blank, s.paperBlank),
                  (PaperStyle.lined, s.paperLined),
                  (PaperStyle.grid, s.paperGrid),
                  (PaperStyle.dotted, s.paperDotted),
                ])
                  CheckedPopupMenuItem(value: p.name, checked: _note.paper == p, child: Text('${s.paper}: $label')),
                const PopupMenuDivider(),
                if (_inkMode) PopupMenuItem(value: 'clear', child: Text(s.clearPage)),
                PopupMenuItem(value: 'delete', child: Text(s.delete)),
              ],
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: content,
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.ink, required this.onChanged});

  final bool ink;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = Theme.of(context).colorScheme;
    Widget seg(bool value, IconData icon, String label) {
      final sel = value == ink;
      return Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: sel ? c.surfaceContainerLowest : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              boxShadow: sel ? softShadow(context, strength: 0.6) : null,
            ),
            child: Icon(icon, size: 20, color: sel ? c.primary : c.onSurfaceVariant),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg(false, Icons.notes_rounded, s.textMode),
        seg(true, Icons.draw_rounded, s.inkMode),
      ]),
    );
  }
}
