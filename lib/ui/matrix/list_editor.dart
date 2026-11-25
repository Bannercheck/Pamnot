import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/task_list.dart';
import '../../state/app_controller.dart';
import '../../theme/pamnot_theme.dart';
import '../common/soft.dart';
import 'list_icons.dart';

/// The sheet that makes a new list (no [list]) or edits [list]: name (40
/// characters at most), colour, icon, Save, and for an existing list Delete,
/// which asks first and can be undone. The last list cannot be deleted.
Future<void> showListEditor(BuildContext context, AppController app, {TaskList? list}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => _ListEditor(app: app, list: list),
    );

class _ListEditor extends StatefulWidget {
  const _ListEditor({required this.app, this.list});

  final AppController app;
  final TaskList? list;

  @override
  State<_ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends State<_ListEditor> {
  static const maxName = 40;

  late final _name = TextEditingController(text: widget.list?.name ?? '');
  late int _color = widget.list?.colorIndex ?? (widget.app.lists.last.colorIndex + 1) % pastels.length;
  late String _icon = widget.list?.icon ?? 'list';

  AppController get _app => widget.app;
  bool get _isNew => widget.list == null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final list = widget.list;
    if (list == null) {
      final l = _app.addList(name, colorIndex: _color, icon: _icon);
      _app.selectList(l.id);
    } else {
      _app.updateList(_app.listById(list.id).copyWith(name: name, colorIndex: _color, icon: _icon));
    }
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final s = S.of(context);
    final c = Theme.of(context).colorScheme;
    final m = ScaffoldMessenger.of(context);
    final list = _app.listById(widget.list!.id);
    final target = _app.lists.firstWhere((l) => l.id != list.id);
    final n = _app.tasks.where((t) => t.listId == list.id).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(s.deleteList),
        content: Text(s.deleteListBody(list.name, n, target.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(s.cancel)),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: c.error),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = _app.deleteList(list.id);
    if (r == null) return;
    Navigator.pop(context);
    showUndoSnack(m, s.listDeleted, () => _app.restoreList(r.list, r.movedTaskIds), s.undo);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final canDelete = _app.lists.length > 1;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_isNew ? s.newList : s.renameList, style: t.textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: _isNew,
              maxLength: maxName,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: s.listNameHint),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            Text(s.color, style: t.textTheme.labelLarge?.copyWith(color: c.onSurfaceVariant)),
            PastelPicker(selected: _color, onChanged: (i) => setState(() => _color = i)),
            const SizedBox(height: 12),
            Text(s.icon, style: t.textTheme.labelLarge?.copyWith(color: c.onSurfaceVariant)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final MapEntry(key: key, value: icon) in listIcons.entries)
                  _IconChoice(
                    icon: icon,
                    label: s.listIconName(key),
                    selected: key == _icon,
                    onTap: () => setState(() => _icon = key),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (!_isNew)
                  Flexible(
                    child: TextButton.icon(
                      key: const Key('list-delete'),
                      style: TextButton.styleFrom(foregroundColor: c.error, minimumSize: const Size(44, 44)),
                      onPressed: canDelete ? _delete : null,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text(s.deleteList),
                    ),
                  ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
                  onPressed: _name.text.trim().isEmpty ? null : _save,
                  child: Text(s.save),
                ),
              ],
            ),
            if (!_isNew && !canDelete)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(s.lastListNote, style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant)),
              ),
          ],
        ),
      ),
    );
  }
}

/// A 44×44 pt icon button of the icon grid, read by the icon's name.
class _IconChoice extends StatelessWidget {
  const _IconChoice({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? c.primaryContainer : Colors.transparent,
        shape: CircleBorder(side: BorderSide(color: selected ? c.primary : c.outline, width: selected ? 2 : 1)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 22, color: selected ? c.onPrimaryContainer : c.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
