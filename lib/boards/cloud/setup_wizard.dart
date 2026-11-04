import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/collab_strings.dart';
import '../../l10n/strings.dart';
import '../../ui/common/soft.dart';
import '../../theme/pamnot_theme.dart';
import 'cloud_api.dart';
import 'cloud_scope.dart';
import 'cloud_service.dart';
import 'cloud_widgets.dart';
import 'server_config.dart';

const supabaseDashboardUrl = 'https://supabase.com/dashboard/projects';
const schemaAsset = 'assets/supabase/schema.sql';

/// The owner's one-time setup (docs/boards/DESIGN.md §7, five steps with
/// copy buttons). True once the device is connected.
Future<bool> showSetupWizard(BuildContext context) async {
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => const SetupWizardPage()),
  );
  return ok == true;
}

class SetupWizardPage extends StatefulWidget {
  const SetupWizardPage({super.key, this.loadSql});

  /// Reads the bundled SQL; tests replace it.
  final Future<String> Function()? loadSql;

  @override
  State<SetupWizardPage> createState() => _SetupWizardPageState();
}

class _SetupWizardPageState extends State<SetupWizardPage> {
  late final CloudService _cloud;

  /// Steps 1–4 are skipped when the server is already known (build-time
  /// preset, or a saved server whose session ended).
  late final CloudConfig? _known;
  late int _step;

  final _url = TextEditingController();
  final _key = TextEditingController();
  final _name = TextEditingController();
  late int _color;

  @override
  void initState() {
    super.initState();
    _cloud = CloudScope.read(context)!;
    _known = _cloud.server;
    _step = _known != null ? 5 : 1;
    _url.text = _known?.url ?? '';
    _key.text = _known?.key ?? '';
    _name.text = _cloud.displayName;
    _color = _cloud.config?.colorIndex ?? math.Random().nextInt(pastels.length);
  }

  String? _urlError, _keyError, _nameError;
  bool _keyIsSecret = false;
  String? _normalized;

  bool _busy = false;
  ConnectStep? _progress;
  CloudProblem? _failure;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showCloudSnack(context, S.of(context).copied);
  }

  Future<void> _copySql() async {
    final sql = await (widget.loadSql ?? () => DefaultAssetBundle.of(context).loadString(schemaAsset))();
    await _copy(sql);
  }

  void _checkUrl(String v) {
    final r = checkServerUrl(v);
    setState(() {
      _normalized = r.url;
      _urlError = null;
    });
  }

  /// Step 4 → 5: both fields must pass before anything goes over the network.
  bool _validateServer() {
    final s = S.of(context);
    final u = checkServerUrl(_url.text);
    final k = checkPublishableKey(_key.text);
    setState(() {
      _urlError = u.problem == null ? null : s.urlProblem(u.problem!);
      _keyError = k == null ? null : s.keyProblem(k);
      _keyIsSecret = k == KeyProblem.secret;
      _normalized = u.url;
    });
    return u.isOk && k == null;
  }

  void _next() {
    if (_step == 4 && !_validateServer()) return;
    setState(() {
      _failure = null;
      _step = math.min(5, _step + 1);
    });
  }

  void _back() => setState(() => _step = math.max(_known != null ? 5 : 1, _step - 1));

  Future<void> _connect() async {
    final s = S.of(context);
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = s.nameRequired);
      return;
    }
    if (_known == null && !_validateServer()) {
      setState(() => _step = 4);
      return;
    }
    setState(() {
      _nameError = null;
      _busy = true;
      _failure = null;
      _progress = null;
    });
    try {
      await _cloud.connect(
        url: _known?.url ?? _url.text,
        key: _known?.key ?? _key.text,
        name: _name.text.trim(),
        colorIndex: _color,
        onStep: (st) {
          if (mounted) setState(() => _progress = st);
        },
      );
      if (!mounted) return;
      setState(() => _progress = ConnectStep.done);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) Navigator.of(context).pop(true);
    } on CloudFailure catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _failure = e.problem;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final first = _known != null ? 5 : 1;
    return Scaffold(
      appBar: AppBar(title: Text(s.setupTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          ContentWidth(
            maxWidth: 680,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_known == null) ...[
                  Text(s.setupIntro, style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 14),
                ],
                for (var n = first; n <= 5; n++) ...[
                  _StepCard(
                    number: n,
                    title: _titleOf(s, n),
                    active: n == _step,
                    done: n < _step,
                    onTap: n < _step && !_busy ? () => setState(() => _step = n) : null,
                    child: n == _step ? _body(s, n) : null,
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _titleOf(S s, int n) => switch (n) {
        1 => s.step1,
        2 => s.step2,
        3 => s.step3,
        4 => s.step4,
        _ => s.step5,
      };

  Widget _nav(S s, {Widget? primary}) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            if (_step > (_known != null ? 5 : 1)) TextButton(onPressed: _busy ? null : _back, child: Text(s.back)),
            primary ?? FilledButton(onPressed: _next, child: Text(s.next)),
          ],
        ),
      );

  Widget _hint(String text) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(text, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
    );
  }

  Widget _body(S s, int n) {
    switch (n) {
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _hint(s.step1Hint),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => _copy(supabaseDashboardUrl),
                icon: const Icon(Icons.link_rounded),
                label: Text(s.copyAddress),
              ),
            ),
            _nav(s),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _hint(s.step2Hint),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: _copySql,
                icon: const Icon(Icons.content_copy_rounded),
                label: Text(s.copySql),
              ),
            ),
            _nav(s),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_hint(s.step3Hint), _nav(s)],
        );
      case 4:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('cloud-url'),
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: s.serverUrl,
                hintText: 'https://abcd….supabase.co',
                errorText: _urlError,
                errorMaxLines: 3,
                helperMaxLines: 2,
                helperText: _normalized != null && _normalized != _url.text.trim() ? s.willUse(_normalized!) : null,
              ),
              onChanged: _checkUrl,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('cloud-key'),
              controller: _key,
              autocorrect: false,
              enableSuggestions: false,
              maxLines: 3,
              minLines: 1,
              style: const TextStyle(fontFamily: 'monospace', fontFamilyFallback: monoFallback, fontSize: 13),
              decoration: InputDecoration(labelText: s.publishableKey, errorText: _keyIsSecret ? null : _keyError, errorMaxLines: 3),
              onChanged: (_) => setState(() {
                _keyError = null;
                _keyIsSecret = false;
              }),
            ),
            if (_keyIsSecret) ...[
              const SizedBox(height: 10),
              Notice(_keyError!, tone: NoticeTone.error),
            ],
            _nav(s),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_known != null) _hint(s.serverOk(_known.host)),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('cloud-name'),
              controller: _name,
              enabled: !_busy,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: s.yourName, helperText: s.yourNameHint, errorText: _nameError),
              onSubmitted: (_) => _connect(),
            ),
            const SizedBox(height: 8),
            Text(s.yourColor, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            PastelPicker(selected: _color, onChanged: (i) => setState(() => _color = i)),
            if (_progress != null || _busy) ...[
              const SizedBox(height: 14),
              for (final st in [ConnectStep.reach, ConnectStep.checkSetup, ConnectStep.signIn, ConnectStep.profile])
                if (_progress != null && _progress!.index >= st.index)
                  BusyLine(_stepText(s, st), done: _progress!.index > st.index || _progress == ConnectStep.done),
              if (_progress == ConnectStep.done)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(s.readyBlossom, style: Theme.of(context).textTheme.titleMedium),
                ),
            ],
            if (_failure != null) ...[
              const SizedBox(height: 14),
              Notice(
                s.cloudProblem(_failure!),
                tone: NoticeTone.error,
                action: s.stepFor(_failure!) != null && _known == null
                    ? TextButton(
                        onPressed: () => setState(() {
                          _step = s.stepFor(_failure!)!;
                          _failure = null;
                        }),
                        child: Text(s.goToStep(s.stepFor(_failure!)!)),
                      )
                    : null,
              ),
            ],
            _nav(
              s,
              primary: FilledButton.icon(
                key: const ValueKey('cloud-connect'),
                onPressed: _busy ? null : _connect,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_done_outlined),
                label: Text(_busy ? s.connecting : s.connect),
              ),
            ),
          ],
        );
    }
  }

  String _stepText(S s, ConnectStep st) => switch (st) {
        ConnectStep.reach => s.stepReach,
        ConnectStep.checkSetup => s.stepCheck,
        ConnectStep.signIn => s.stepSignIn,
        _ => s.stepProfile,
      };
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.active,
    required this.done,
    this.onTap,
    this.child,
  });

  final int number;
  final String title;
  final bool active;
  final bool done;
  final VoidCallback? onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    return SoftCard(
      shadow: active,
      color: active ? c.surfaceContainerLowest : c.surfaceContainer,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: done ? c.tertiaryContainer : c.primaryContainer, shape: BoxShape.circle),
                child: done
                    ? Icon(Icons.check_rounded, size: 18, color: c.onTertiaryContainer)
                    : Text('$number', style: t.textTheme.labelLarge?.copyWith(color: c.onPrimaryContainer, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    title,
                    style: (active ? t.textTheme.titleSmall : t.textTheme.bodyMedium)
                        ?.copyWith(color: active ? c.onSurface : c.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
          if (child != null) Padding(padding: const EdgeInsets.only(left: 40), child: child),
        ],
      ),
    );
  }
}
