import 'package:flutter/material.dart';

import '../../l10n/board_strings.dart';
import '../../l10n/strings.dart';
import '../../state/app_scope.dart';
import '../../theme/pamnot_theme.dart';
import '../../ui/common/prediction_bar.dart';
import '../../ui/common/soft.dart';
import '../boards_controller.dart';
import '../boards_repository.dart';
import 'board_page.dart';

/// "Yeni pano": name, template and colour, then the new board opens.
Future<void> showNewBoardSheet(BuildContext context) async {
  final id = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => const NewBoardSheet(),
  );
  if (id != null && context.mounted) await BoardPage.open(context, id);
}

class NewBoardSheet extends StatefulWidget {
  const NewBoardSheet({super.key});

  @override
  State<NewBoardSheet> createState() => _NewBoardSheetState();
}

class _NewBoardSheetState extends State<NewBoardSheet> {
  final _name = TextEditingController();
  final _focus = FocusNode();
  final _barKey = GlobalKey<State<PredictionBar>>();
  BoardTemplate _template = BoardTemplate.tasks;
  late int _color = (AppScope.of(context).boards.boards.length + 3) % pastels.length;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) return;
    _busy = true;
    final s = S.of(context);
    final boards = AppScope.of(context).boards;
    final name = _name.text.trim();
    final id = await boards.createBoard(
      title: name.isEmpty ? s.newBoard : name,
      colorIndex: _color,
      template: _template,
      strings: s,
    );
    // Someone who picked the blank canvas wants the canvas, even on a phone.
    if (_template == BoardTemplate.blank) boards.saveView(id, const BoardViewState(view: 'canvas'));
    if (mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
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
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                children: [
                  Text(s.newBoard, style: t.textTheme.titleLarge),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _name,
                    focusNode: _focus,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    style: t.textTheme.titleMedium,
                    decoration: InputDecoration(labelText: s.boardName, hintText: s.boardNameHint),
                    onSubmitted: (_) => _create(),
                  ),
                  const SizedBox(height: 16),
                  _TemplateCard(
                    icon: Icons.view_kanban_outlined,
                    title: s.taskBoardTemplate,
                    subtitle: s.taskBoardTemplateSub,
                    selected: _template == BoardTemplate.tasks,
                    onTap: () => setState(() => _template = BoardTemplate.tasks),
                  ),
                  const SizedBox(height: 10),
                  _TemplateCard(
                    icon: Icons.gesture_rounded,
                    title: s.blankCanvasTemplate,
                    subtitle: s.blankCanvasTemplateSub,
                    selected: _template == BoardTemplate.blank,
                    onTap: () => setState(() => _template = BoardTemplate.blank),
                  ),
                  const SizedBox(height: 18),
                  Text(s.color, style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  PastelPicker(selected: _color, onChanged: (i) => setState(() => _color = i)),
                  const SizedBox(height: 22),
                  FilledButton(onPressed: _create, child: Text(s.create)),
                ],
              ),
            ),
          ),
          PredictionBar(key: _barKey, fields: [PredictiveField(_name, _focus)]),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? c.primaryContainer : c.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: selected ? c.primary.withValues(alpha: 0.5) : c.outlineVariant, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Icon(icon, color: selected ? c.onPrimaryContainer : c.onSurfaceVariant),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: t.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(subtitle, style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: selected ? 1 : 0,
                  child: Icon(Icons.check_circle_rounded, color: c.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
