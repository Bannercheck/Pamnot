import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../l10n/strings.dart';
import '../../models/note.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../common/page_header.dart';
import '../common/soft.dart';
import 'note_card.dart';
import 'note_editor_page.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context, {Slice.notes});
    final s = S.of(context);
    final notes = app.sortedNotes(query: _query);
    final now = app.now();
    return Scaffold(
      floatingActionButton: NewNoteButtons(app: app),
      body: LayoutBuilder(builder: (context, c) {
        final columns = c.maxWidth < 560 ? 2 : c.maxWidth < 900 ? 3 : c.maxWidth < 1300 ? 4 : 5;
        final pad = c.maxWidth < 560 ? 16.0 : 28.0;
        return CustomScrollView(
          slivers: [
            PageHeader(title: s.notes),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 4, pad, 16),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: s.searchNotes,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(() {
                              _search.clear();
                              _query = '';
                            }),
                          ),
                  ),
                ),
              ),
            ),
            if (notes.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(emoji: _query.isEmpty ? '📝' : '🔍', text: _query.isEmpty ? s.noNotes : s.noResults),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, 120),
                sliver: SliverMasonryGrid.count(
                  crossAxisCount: columns,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childCount: notes.length,
                  itemBuilder: (context, i) {
                    final n = notes[i];
                    return NoteCard(
                      key: ValueKey(n.id),
                      note: n,
                      now: now,
                      onTap: () => NoteEditorPage.open(context, n),
                      onLongPress: () => showNoteActions(context, app, n),
                    );
                  },
                ),
              ),
          ],
        );
      }),
    );
  }
}

class NewNoteButtons extends StatelessWidget {
  const NewNoteButtons({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.small(
          heroTag: 'ink-note',
          tooltip: s.newHandwriting,
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
          onPressed: () => NoteEditorPage.open(context, app.draftNote(handwriting: true), ink: true),
          child: const Icon(Icons.draw_rounded),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'text-note',
          onPressed: () => NoteEditorPage.open(context, app.draftNote()),
          icon: const Icon(Icons.add_rounded),
          label: Text(s.newNote),
        ),
      ],
    );
  }
}

Future<void> showNoteActions(BuildContext context, AppController app, Note n) {
  final s = S.of(context);
  final messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(n.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined),
              title: Text(n.pinned ? s.unpin : s.pin),
              onTap: () {
                app.togglePin(n.id);
                Navigator.pop(sheet);
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: PastelPicker(
                selected: n.colorIndex,
                onChanged: (i) {
                  app.upsertNote(n.copyWith(colorIndex: i));
                  Navigator.pop(sheet);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text(s.delete),
              onTap: () {
                Navigator.pop(sheet);
                final removed = app.deleteNote(n.id);
                if (removed != null) {
                  messenger.hideCurrentSnackBar();
                  messenger.showSnackBar(SnackBar(
                    content: Text(s.deleted),
                    action: SnackBarAction(label: s.undo, onPressed: () => app.restoreNote(removed)),
                  ));
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}
