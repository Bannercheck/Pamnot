import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/task_list.dart';
import '../../state/app_controller.dart';
import '../common/glass.dart';
import '../common/soft.dart';
import '../settings/settings_page.dart';
import 'habits_page.dart';
import 'list_editor.dart';
import 'list_icons.dart';

enum _More { habits, settings }

/// The glass strip at the top of the Matrix screen: one chip per list
/// (scrolls sideways), **+** for a new list, and the ⋯ menu (Habits,
/// Settings). Tap a chip to show that list, long-press it to edit it.
class ListTabs extends StatefulWidget {
  const ListTabs({super.key, required this.app});

  final AppController app;

  @override
  State<ListTabs> createState() => _ListTabsState();
}

class _ListTabsState extends State<ListTabs> {
  final _selectedKey = GlobalKey();
  String? _shown;

  /// Keeps the selected chip on screen, e.g. a list chosen elsewhere or the
  /// last one of many.
  void _revealSelected() {
    final id = widget.app.currentListId;
    if (id == _shown) return;
    _shown = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _selectedKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(ctx, alignment: 0.5, duration: motion(ctx, const Duration(milliseconds: 250)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = S.of(context);
    final current = app.currentListId;
    _revealSelected();
    return GlassPanel(
      radius: 26,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final l in app.lists)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 4),
                      child: _ListChip(
                        key: Key('list-tab-${l.id}'),
                        list: l,
                        selected: l.id == current,
                        anchor: l.id == current ? _selectedKey : null,
                        onTap: () => app.selectList(l.id),
                        onLongPress: () => showListEditor(context, app, list: l),
                      ),
                    ),
                  IconButton(
                    key: const Key('list-add'),
                    tooltip: s.newList,
                    onPressed: () => showListEditor(context, app),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<_More>(
            key: const Key('matrix-more'),
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (v) => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => switch (v) {
                _More.habits => const HabitsPage(),
                _More.settings => const SettingsPage(),
              },
            )),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _More.habits,
                child: ListTile(leading: const Icon(Icons.spa_outlined), title: Text(s.habits)),
              ),
              PopupMenuItem(
                value: _More.settings,
                child: ListTile(leading: const Icon(Icons.tune_rounded), title: Text(s.settings)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ListChip extends StatelessWidget {
  const _ListChip({
    super.key,
    required this.list,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    this.anchor,
  });

  final TaskList list;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final GlobalKey? anchor;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final fg = selected ? c.onPrimaryContainer : c.onSurface;
    return Semantics(
      key: anchor,
      button: true,
      selected: selected,
      onLongPressHint: s.renameList,
      child: Material(
        color: selected ? c.primaryContainer : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PastelDot(list.colorIndex),
                  const SizedBox(width: 6),
                  Icon(listIconOf(list.icon), size: 18, color: fg),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(
                      list.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.labelLarge?.copyWith(color: fg),
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
