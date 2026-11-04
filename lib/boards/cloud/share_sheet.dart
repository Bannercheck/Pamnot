import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/collab_strings.dart';
import '../../l10n/strings.dart';
import '../boards_controller.dart';
import '../connection.dart';
import '../model/board_doc.dart';
import '../sync/backend.dart';
import 'cloud_scope.dart';
import 'cloud_service.dart';
import 'cloud_widgets.dart';
import 'invite.dart';
import 'join_sheet.dart';
import 'members.dart';
import 'setup_wizard.dart';

export 'join_sheet.dart' show showJoinSheet;
export 'remove_board.dart' show confirmRemoveBoard;

/// "Paylaş": set-up prompt, upload, invite text, members (DESIGN.md §7).
Future<void> showShareSheet(BuildContext context, {required BoardsController boards, required String boardId}) async {
  final next = await showCloudSheet<_After>(context, (_) => ShareSheet(boards: boards, boardId: boardId));
  if (next == _After.join && context.mounted) await showJoinSheet(context, boards: boards);
}

enum _After { join }

enum _Phase { loading, setup, confirm, uploading, shared, readOnly, gone }

class ShareSheet extends StatefulWidget {
  const ShareSheet({super.key, required this.boards, required this.boardId});

  final BoardsController boards;
  final String boardId;

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  CloudService? _cloud;

  /// Held open while the sheet shows, so an upload keeps going and presence
  /// stays live even when the sheet was opened from the list.
  OpenBoard? _board;
  bool _released = false;
  bool _missing = false;

  int _uploadTotal = 0;
  bool _starting = false;

  // Shared phase
  bool _loadingShared = false;
  String? _code;
  bool? _isOwner;
  List<BoardMember>? _members;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final b = await widget.boards.open(widget.boardId);
    if (!mounted || _released) {
      if (b != null) await widget.boards.release(b);
      return;
    }
    setState(() {
      _board = b;
      _missing = b == null;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cloud = CloudScope.maybeOf(context);
  }

  @override
  void dispose() {
    _released = true;
    final b = _board;
    if (b != null) unawaited(widget.boards.release(b));
    super.dispose();
  }

  /// The board's id now: an upload that hit an id collision re-mints it.
  String get _id => _board?.id ?? widget.boardId;

  _Phase get _phase {
    final b = _board;
    if (b == null) return _missing || widget.boards.summary(_id) == null ? _Phase.gone : _Phase.loading;
    final doc = b.doc;
    final cloud = _cloud;
    if (doc.readOnly) return _Phase.readOnly;
    if (cloud == null || !cloud.ready.value) return _Phase.setup;
    if (doc.state == BoardState.local) return _starting ? _Phase.uploading : _Phase.confirm;
    if (doc.account != cloud.account) return _Phase.gone;
    if (doc.state == BoardState.uploading || (_uploadTotal > 0 && doc.pendingCount > 0)) return _Phase.uploading;
    return _Phase.shared;
  }

  Future<void> _setup() async {
    final ok = await showSetupWizard(context);
    if (ok && mounted) setState(() {});
  }

  Future<void> _upload() async {
    final cloud = _cloud, b = _board;
    final acc = cloud?.account;
    if (b == null || acc == null) return;
    setState(() => _starting = true);
    await widget.boards.beginUpload(_id, acc);
    if (!mounted) return;
    setState(() {
      _uploadTotal = b.doc.pendingCount;
      _starting = false;
    });
  }

  Future<void> _loadShared() async {
    final backend = _cloud?.backend, acc = _cloud?.account;
    if (backend == null || acc == null || _loadingShared) return;
    setState(() {
      _loadingShared = true;
      _error = null;
    });
    try {
      final status = await backend.boardStatus(_id);
      final owner = status?.ownerId == acc.userId;
      final results = await Future.wait([
        backend.members(_id),
        if (owner) backend.getInvite(_id),
      ]);
      if (!mounted) return;
      setState(() {
        _isOwner = owner;
        _members = results[0] as List<BoardMember>;
        _code = owner ? results[1] as String? : null;
      });
    } on BackendUnavailable {
      if (mounted) setState(() => _error = S.of(context).needsInternet);
    } on AccessDenied {
      if (mounted) setState(() => _error = S.of(context).accessRemoved);
    } on Exception {
      if (mounted) setState(() => _error = S.of(context).needsInternet);
    } finally {
      if (mounted) setState(() => _loadingShared = false);
    }
  }

  String? get _inviteText {
    final server = _cloud?.server, code = _code;
    if (server == null || code == null) return null;
    final title = _board?.doc.meta?.title ?? '';
    final token = Invite(url: server.url, key: server.key, code: code, title: title).encode();
    return S.of(context).inviteMessage(title, token);
  }

  Future<void> _copyInvite() async {
    final text = _inviteText;
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showCloudSnack(context, S.of(context).copied);
  }

  Future<void> _rotate() async {
    final s = S.of(context);
    final backend = _cloud?.backend;
    if (backend == null) return;
    final ok = await confirmCloudAction(context, title: s.resetInvite, body: s.resetInviteBody, confirm: s.resetInvite);
    if (!ok) return;
    try {
      final code = await backend.rotateInvite(_id);
      if (mounted) setState(() => _code = code);
    } on Exception {
      if (mounted) showCloudSnack(context, s.needsInternet);
    }
  }

  Future<void> _remove(BoardMember m) async {
    final s = S.of(context);
    final backend = _cloud?.backend;
    if (backend == null) return;
    final name = m.displayName.trim().isEmpty ? s.noName : m.displayName;
    final ok = await confirmCloudAction(
      context,
      title: s.removeFromBoard,
      body: s.removeMemberBody(name),
      confirm: s.removeFromBoard,
      destructive: true,
    );
    if (!ok) return;
    try {
      final code = await backend.removeMember(_id, m.userId);
      if (!mounted) return;
      setState(() {
        _code = code;
        _members = [...?_members?.where((x) => x.userId != m.userId)];
      });
    } on Exception {
      if (mounted) showCloudSnack(context, s.needsInternet);
    }
  }

  Future<void> _keepCopy() async {
    final s = S.of(context);
    final id = await widget.boards.saveLocalCopy(_id);
    if (!mounted) return;
    Navigator.pop(context);
    if (id != null) showCloudSnack(context, s.localCopySaved);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    // Connections are replaced on sign-in and upload: listen to the boards,
    // then to whichever connection the board has now.
    return ListenableBuilder(
      listenable: Listenable.merge([widget.boards, if (_cloud != null) _cloud!.ready]),
      builder: (context, _) {
        final b = _board;
        if (b == null) {
          return _phase == _Phase.gone
              ? CloudSheetBody(title: s.shareWithTeam, children: [Notice(s.notSharedAnymore)])
              : const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
        }
        return ValueListenableBuilder<SyncState>(
          valueListenable: b.connection.state,
          builder: (context, state, _) => _content(s, b, state),
        );
      },
    );
  }

  Widget _content(S s, OpenBoard b, SyncState state) {
    final phase = _phase;
    if (phase == _Phase.shared && _members == null && !_loadingShared && _error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadShared());
      });
    }
    switch (phase) {
      case _Phase.loading:
        return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
      case _Phase.gone:
        return CloudSheetBody(title: s.shareWithTeam, children: [Notice(s.notSharedAnymore)]);
      case _Phase.setup:
        return CloudSheetBody(
          title: s.shareWithTeam,
          icon: Icons.group_add_outlined,
          children: [
            Text(s.shareNotSetUp, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: _setup, icon: const Icon(Icons.auto_awesome_rounded), label: Text(s.startSetup)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, _After.join),
              icon: const Icon(Icons.mail_outline_rounded),
              label: Text(s.haveInvite),
            ),
            const SizedBox(height: 4),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(s.notNow)),
          ],
        );
      case _Phase.confirm:
        return CloudSheetBody(
          title: s.shareBoard,
          icon: Icons.cloud_upload_outlined,
          children: [
            Notice(s.uploadNotice, tone: NoticeTone.warning),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const ValueKey('share-upload'),
              onPressed: _upload,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(s.share),
            ),
            const SizedBox(height: 4),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
          ],
        );
      case _Phase.uploading:
        final total = _uploadTotal == 0 ? b.doc.pendingCount : _uploadTotal;
        final left = b.doc.pendingCount;
        final done = (total - left).clamp(0, total);
        return CloudSheetBody(
          title: s.shareBoard,
          icon: Icons.cloud_upload_outlined,
          children: [
            BusyLine(s.uploading(done, total), value: total == 0 ? null : done / total),
            if (state.status == SyncStatus.offline) ...[const SizedBox(height: 10), Notice(s.uploadOffline)],
            if (state.status == SyncStatus.error) ...[
              const SizedBox(height: 10),
              Notice(
                state.message ?? s.uploadFailed,
                tone: NoticeTone.error,
                action: TextButton(onPressed: () => unawaited(b.connection.retry()), child: Text(s.tryAgain)),
              ),
            ],
          ],
        );
      case _Phase.readOnly:
        return CloudSheetBody(
          title: s.shareWithTeam,
          children: [
            Notice(b.doc.state == BoardState.deleted ? s.boardDeletedByOwner : s.accessRemoved, tone: NoticeTone.warning),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: _keepCopy, icon: const Icon(Icons.save_alt_rounded), label: Text(s.keepLocalCopy)),
          ],
        );
      case _Phase.shared:
        return _sharedView(s, b);
    }
  }

  Widget _sharedView(S s, OpenBoard b) {
    final t = Theme.of(context);
    final invite = _inviteText;
    return CloudSheetBody(
      title: s.shareBoard,
      icon: Icons.group_outlined,
      children: [
        if (_error != null)
          Notice(_error!, tone: NoticeTone.error, action: TextButton(onPressed: _loadShared, child: Text(s.tryAgain)))
        else if (_members == null)
          BusyLine(s.connecting)
        else ...[
          if (_isOwner == true && invite != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: t.colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(18)),
              child: SelectableText(invite, style: const TextStyle(fontFamily: 'monospace', fontFamilyFallback: monoFallback, fontSize: 13, height: 1.4)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('share-copy'),
                  onPressed: _copyInvite,
                  icon: const Icon(Icons.content_copy_rounded),
                  label: Text(s.copyInvite),
                ),
                OutlinedButton.icon(onPressed: _rotate, icon: const Icon(Icons.refresh_rounded), label: Text(s.resetInvite)),
              ],
            ),
          ] else if (_isOwner == false)
            Notice(s.inviteOwnerOnly),
          const SizedBox(height: 10),
          SectionHeaderLite(s.members),
          MembersList(
            members: _members!,
            peers: b.connection.peers,
            me: _cloud?.account,
            isOwner: _isOwner == true,
            onRemove: _remove,
          ),
        ],
      ],
    );
  }
}

/// A small heading inside sheets.
class SectionHeaderLite extends StatelessWidget {
  const SectionHeaderLite(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}
