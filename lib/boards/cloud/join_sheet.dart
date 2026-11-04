import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/collab_strings.dart';
import '../../l10n/strings.dart';
import '../../theme/pamnot_theme.dart';
import '../boards_controller.dart';
import '../sync/backend.dart';
import 'cloud_api.dart';
import 'cloud_scope.dart';
import 'cloud_service.dart';
import 'cloud_widgets.dart';
import 'invite.dart';

/// "Davete katıl": paste an invite, join, returns the joined board's id.
Future<String?> showJoinSheet(BuildContext context, {required BoardsController boards}) =>
    showCloudSheet<String>(context, (_) => JoinSheet(boards: boards));

class JoinSheet extends StatefulWidget {
  const JoinSheet({super.key, required this.boards, this.readClipboard});

  final BoardsController boards;

  /// Reads the clipboard text; tests replace it.
  final Future<String?> Function()? readClipboard;

  @override
  State<JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<JoinSheet> {
  final _text = TextEditingController();
  final _name = TextEditingController();
  bool _named = false;
  Invite? _invite;
  String? _busy;
  String? _error;
  String? _nameError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_named) {
      _named = true;
      _name.text = CloudScope.read(context)?.displayName ?? '';
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _name.dispose();
    super.dispose();
  }

  void _parse(String text) => setState(() {
        _invite = Invite.find(text);
        _error = null;
      });

  Future<void> _paste() async {
    final read = widget.readClipboard ?? () async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    final text = await read();
    if (text == null || !mounted) return;
    _text.text = text;
    _parse(text);
  }

  Future<void> _join(CloudService cloud, Invite inv) async {
    final s = S.of(context);
    final needsSignIn = !cloud.ready.value;
    if (needsSignIn && _name.text.trim().isEmpty) {
      setState(() => _nameError = s.nameRequired);
      return;
    }
    setState(() {
      _nameError = null;
      _error = null;
      _busy = needsSignIn ? s.connecting : s.joining;
    });
    try {
      if (needsSignIn) {
        final saved = cloud.server;
        await cloud.connect(
          // A known server keeps its own key; a new one comes from the invite.
          url: saved?.host == inv.host ? saved!.url : inv.url,
          key: saved?.host == inv.host ? saved!.key : inv.key,
          name: _name.text.trim(),
          colorIndex: cloud.config?.colorIndex ?? math.Random().nextInt(pastels.length),
        );
        if (!mounted) return;
        setState(() => _busy = s.joining);
      }
      final backend = cloud.backend, account = cloud.account;
      if (backend == null || account == null) throw const BackendUnavailable();
      final joined = await backend.joinBoard(inv.code);
      if (!mounted) return;
      if (joined == null) {
        setState(() {
          _busy = null;
          _error = s.inviteInvalid;
        });
        return;
      }
      setState(() => _busy = s.downloadingBoard);
      final title = joined.title.isNotEmpty ? joined.title : inv.title;
      await widget.boards.addJoined(boardId: joined.boardId, title: title, account: account);
      if (mounted) Navigator.pop(context, joined.boardId);
    } on CloudFailure catch (e) {
      _fail(s.cloudProblem(e.problem));
    } on RateLimited {
      _fail(s.tooManyTries);
    } on AccessDenied {
      _fail(s.inviteInvalid);
    } on BackendUnavailable {
      _fail(s.needsInternet);
    }
  }

  void _fail(String message) {
    if (mounted) {
      setState(() {
        _busy = null;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final cloud = CloudScope.maybeOf(context);
    final inv = _invite;
    final server = cloud?.server;
    final otherServer = inv != null && server != null && server.host != inv.host && cloud?.config != null;
    final needsSignIn = cloud != null && !cloud.ready.value;
    final canJoin = cloud != null && inv != null && !otherServer && _busy == null;
    return CloudSheetBody(
      title: s.joinWithInvite,
      icon: Icons.group_add_outlined,
      children: [
        TextField(
          key: const ValueKey('join-text'),
          controller: _text,
          minLines: 2,
          maxLines: 5,
          enabled: _busy == null,
          style: t.textTheme.bodyMedium,
          decoration: InputDecoration(
            labelText: s.pasteInvite,
            hintText: 'PMN1.…',
            errorText: _text.text.trim().isNotEmpty && inv == null ? s.inviteNotFound : null,
          ),
          onChanged: _parse,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const ValueKey('join-paste'),
            onPressed: _busy == null ? _paste : null,
            icon: const Icon(Icons.content_paste_rounded),
            label: Text(s.paste),
          ),
        ),
        if (inv != null) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.dashboard_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '«${inv.title}» · ${inv.host}',
                  key: const ValueKey('join-preview'),
                  style: t.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (otherServer)
            Notice(s.inviteOtherServer, tone: NoticeTone.warning)
          else if (cloud?.config == null)
            Notice(s.inviteWillConnect(inv.host)),
          if (!otherServer && needsSignIn) ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('join-name'),
              controller: _name,
              enabled: _busy == null,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: s.yourName, helperText: s.yourNameHint, errorText: _nameError),
            ),
          ],
        ],
        if (_error != null) ...[const SizedBox(height: 12), Notice(_error!, tone: NoticeTone.error)],
        if (_busy != null) BusyLine(_busy!),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const ValueKey('join-go'),
          onPressed: canJoin ? () => unawaited(_join(cloud, inv)) : null,
          icon: const Icon(Icons.login_rounded),
          label: Text(s.join),
        ),
      ],
    );
  }
}
