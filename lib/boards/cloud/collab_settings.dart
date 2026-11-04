import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/collab_strings.dart';
import '../../l10n/strings.dart';
import '../../state/app_scope.dart';
import '../../ui/common/soft.dart';
import '../boards_controller.dart';
import '../model/board_doc.dart';
import 'cloud_scope.dart';
import 'cloud_service.dart';
import 'cloud_widgets.dart';
import 'join_sheet.dart';
import 'setup_wizard.dart';

/// Settings › "Ortak çalışma" (server, name, colour, disconnect).
class CollabSettingsSection extends StatelessWidget {
  const CollabSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final cloud = CloudScope.maybeOf(context);
    if (cloud == null) return const SizedBox.shrink();
    final s = S.of(context);
    final host = cloud.host;
    if (!cloud.ready.value) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              cloud.config != null && host != null ? s.serverNotSignedIn(host) : s.collabOff,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('collab-setup'),
                  onPressed: () => showSetupWizard(context),
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text(cloud.config != null ? s.connect : s.setUp),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('collab-join'),
                  onPressed: () async {
                    final id = await showJoinSheet(context, boards: AppScope.of(context).boards);
                    if (id != null && context.mounted) showCloudSnack(context, s.joinedBoard);
                  },
                  icon: const Icon(Icons.mail_outline_rounded),
                  label: Text(s.haveInvite),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return _ConnectedTiles(cloud: cloud);
  }
}

class _ConnectedTiles extends StatefulWidget {
  const _ConnectedTiles({required this.cloud});

  final CloudService cloud;

  @override
  State<_ConnectedTiles> createState() => _ConnectedTilesState();
}

class _ConnectedTilesState extends State<_ConnectedTiles> {
  late final _name = TextEditingController(text: widget.cloud.displayName);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _saveName();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _saveName() {
    final n = _name.text.trim();
    if (n.isEmpty) {
      _name.text = widget.cloud.displayName;
      return;
    }
    if (n != widget.cloud.displayName) unawaited(widget.cloud.updateProfile(name: n));
  }

  Future<void> _disconnect() async {
    final s = S.of(context);
    final boards = AppScope.of(context).boards;
    final unsent = await unsentChanges(boards, widget.cloud.account);
    if (!mounted) return;
    final ok = await confirmCloudAction(
      context,
      title: s.disconnectDevice,
      body: s.disconnectBody(unsent),
      confirm: s.disconnect,
      destructive: true,
    );
    if (ok) await widget.cloud.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final cloud = widget.cloud;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: Icon(Icons.cloud_done_outlined, color: t.colorScheme.tertiary),
          title: Text(s.serverOk(cloud.host ?? '')),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: TextField(
            key: const ValueKey('collab-name'),
            controller: _name,
            focusNode: _focus,
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: s.yourName, helperText: s.yourNameHint),
            onSubmitted: (_) => _saveName(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.yourColor, style: t.textTheme.titleSmall),
              const SizedBox(height: 8),
              PastelPicker(
                selected: cloud.colorIndex,
                onChanged: (i) => unawaited(cloud.updateProfile(colorIndex: i)),
              ),
            ],
          ),
        ),
        ListTile(
          key: const ValueKey('collab-disconnect'),
          leading: Icon(Icons.link_off_rounded, color: t.colorScheme.error),
          title: Text(s.disconnectDevice, style: TextStyle(color: t.colorScheme.error)),
          onTap: _disconnect,
        ),
      ],
    );
  }
}

/// Items with changes this device has not got confirmed yet, over the shared
/// boards of [account]. Loads each board's document: for the disconnect
/// dialog only, never on a hot path.
Future<int> unsentChanges(BoardsController boards, BoardAccount? account) async {
  if (account == null) return 0;
  await boards.flush();
  var n = 0;
  for (final b in boards.boards.where((b) => b.account == account && b.shared)) {
    final doc = boards.openBoard(b.id)?.doc ?? await boards.repo.loadBoard(b.id);
    n += doc?.pendingCount ?? 0;
  }
  return n;
}
