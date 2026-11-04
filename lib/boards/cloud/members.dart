import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/collab_strings.dart';
import '../../l10n/strings.dart';
import '../connection.dart';
import '../model/board_doc.dart';
import '../sync/backend.dart';
import 'cloud_widgets.dart';

/// Üyeler: everyone on the board with presence from the open board's
/// connection, '(sen)', 'Sahip', and the owner's 'Panodan çıkar'.
class MembersList extends StatelessWidget {
  const MembersList({
    super.key,
    required this.members,
    required this.peers,
    required this.me,
    required this.isOwner,
    this.onRemove,
  });

  final List<BoardMember> members;

  /// Others on the board right now (not this device).
  final ValueListenable<List<Peer>> peers;
  final BoardAccount? me;
  final bool isOwner;
  final void Function(BoardMember member)? onRemove;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    return ValueListenableBuilder<List<Peer>>(
      valueListenable: peers,
      builder: (context, here, _) {
        final online = {for (final p in here) p.userId};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final m in members)
              Builder(builder: (context) {
                final self = m.userId == me?.userId;
                final present = self || online.contains(m.userId);
                final name = m.displayName.trim().isEmpty ? s.noName : m.displayName;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: PersonAvatar(name: name, colorIndex: m.colorIndex, online: present),
                  title: Text.rich(TextSpan(children: [
                    TextSpan(text: name),
                    if (self) TextSpan(text: ' ${s.you}', style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
                  ])),
                  subtitle: Text(present ? s.hereNow : s.offline),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (m.role == 'owner')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: t.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(s.owner, style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.onPrimaryContainer)),
                        ),
                      if (isOwner && !self && m.role != 'owner' && onRemove != null)
                        PopupMenuButton<int>(
                          tooltip: s.removeFromBoard,
                          icon: const Icon(Icons.more_horiz_rounded),
                          onSelected: (_) => onRemove!(m),
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 0,
                              child: ListTile(
                                leading: const Icon(Icons.person_remove_outlined),
                                title: Text(s.removeFromBoard),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}
