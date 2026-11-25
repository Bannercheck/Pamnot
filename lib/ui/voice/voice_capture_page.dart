import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/dates.dart';
import '../../core/spoken/spoken_task.dart';
import '../../l10n/strings.dart';
import '../../models/task_list.dart';
import '../../services/links.dart';
import '../../services/speech/speech_engine.dart';
import '../../state/app_scope.dart';
import '../common/format.dart';
import '../common/soft.dart';
import 'voice_capture_controller.dart';

/// The full-screen "Add by voice" screen (design §5, §6.6; compliance §4.1).
/// It only draws [VoiceCaptureController]; every timing lives there.
class VoiceCapturePage extends StatefulWidget {
  /// [engine] null uses the app's engine (`AppController.speech`).
  const VoiceCapturePage({super.key, this.engine, this.autoListen = true});

  final SpeechEngine? engine;

  /// False when a pamnot:// link opened the screen: it waits for a tap
  /// before it listens (see [VoiceCaptureController.open]).
  final bool autoListen;

  static bool _open = false;

  /// The showing screen's answer to a new voice request.
  static VoidCallback? _onRequest;

  /// A screen opened with [open] is showing.
  static bool get isOpen => _open;

  /// A new voice request (the shortcut run again) while a screen is showing:
  /// it listens if its microphone waits for a tap (paused, saved, error), as
  /// a tap would; while listening, previewing or editing nothing happens.
  static void requestAgain() => _onRequest?.call();

  /// Opens the screen full screen on the root navigator; does nothing while
  /// one is already open. When it closes having saved something, a summary
  /// snack bar is shown where it was opened from. [autoListen] false (a
  /// pamnot:// link) opens it paused, waiting for a tap.
  static Future<void> open(BuildContext context, {bool autoListen = true}) async {
    if (_open) return;
    _open = true;
    try {
      // Taken before the push: this context may be gone when the screen
      // closes. Inside the try, so a failed lookup cannot leave [isOpen] set.
      final messenger = ScaffoldMessenger.maybeOf(context);
      final s = S.of(context);
      final saved = await Navigator.of(
        context,
        rootNavigator: true,
      ).push<int>(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => VoiceCapturePage(autoListen: autoListen)),
      );
      if (saved != null && saved > 0) {
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(s.voiceSummary(saved))));
      }
    } finally {
      _open = false;
    }
  }

  @override
  State<VoiceCapturePage> createState() => _VoiceCapturePageState();
}

/// Phases in which the microphone button is shown. In the others it could
/// do nothing (and must not ask for a permission again).
const _micPhases = {
  VoicePhase.preparing,
  VoicePhase.listening,
  VoicePhase.preview,
  VoicePhase.editing,
  VoicePhase.saved,
  VoicePhase.paused,
  VoicePhase.error,
};

/// Phases in which a tap on the microphone starts or stops listening.
const _micActivePhases = {VoicePhase.listening, VoicePhase.saved, VoicePhase.paused, VoicePhase.error};

/// Phases shown on the error card.
const _errorPhases = {
  VoicePhase.error,
  VoicePhase.permissionDenied,
  VoicePhase.dictationOff,
  VoicePhase.unsupportedLocale,
  VoicePhase.unsupportedPlatform,
};

class _VoiceCapturePageState extends State<VoiceCapturePage> with SingleTickerProviderStateMixin {
  late final VoiceCaptureController _c;
  late final AppLifecycleListener _lifecycle;

  /// Runs over [VoiceTimings.previewHold] while a preview waits to be saved.
  late final AnimationController _countdown;

  /// The correction draft; filled from what was heard on entering editing.
  final _draft = TextEditingController();

  /// The phase last seen, to act on phase changes only.
  VoicePhase? _phase;

  /// The preview shown is saved by the controller's timer (VoiceOver was off
  /// and the listen did not end with an error when it appeared).
  bool _timedPreview = false;

  /// The route has been closed (it is closed once).
  bool _left = false;

  @override
  void initState() {
    super.initState();
    final app = AppScope.of(context);
    _c = VoiceCaptureController(
      app: app,
      engine: widget.engine ?? app.speech,
      // The phone's languages (the binding's dispatcher is the platform's).
      deviceLocales: () => WidgetsBinding.instance.platformDispatcher.locales,
      // The microphone is off at this point; iOS mutes haptics while recording.
      onSaved: () => unawaited(HapticFeedback.lightImpact()),
    );
    _countdown = AnimationController(vsync: this, duration: VoiceTimings.previewHold);
    _lifecycle = AppLifecycleListener(onStateChange: _c.onLifecycle);
    unawaited(_c.open(lifecycle: WidgetsBinding.instance.lifecycleState, autoListen: widget.autoListen));
    // After open(): it can change the phase at once (unsupported platform),
    // and the first build shows that anyway.
    _phase = _c.phase;
    _c.addListener(_onChange);
    VoiceCapturePage._onRequest = _c.onVoiceRequest;
  }

  void _onChange() {
    final phase = _c.phase;
    if (phase != _phase) {
      _phase = phase;
      _enter(phase);
    }
    if (phase == VoicePhase.closed) return _leave();
    setState(() {});
  }

  void _enter(VoicePhase phase) {
    if (phase == VoicePhase.preview) {
      // Not after a recogniser error or with VoiceOver: saved by hand.
      _timedPreview = _c.previewOnTimer;
      if (_timedPreview) _countdown.forward(from: 0);
    } else {
      _countdown.stop();
    }
    if (phase == VoicePhase.editing) {
      final text = _c.transcript;
      _draft.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  /// Closes this screen's route, returning how many things it saved.
  void _leave() {
    if (_left || !mounted) return;
    _left = true;
    final route = ModalRoute.of(context);
    // Shown as the navigator's first route (not through [open]): nothing to
    // close back to.
    if (route == null || route.isFirst) return;
    final count = _c.saved.length;
    if (route.isCurrent) {
      Navigator.of(context).pop(count);
    } else if (route.isActive) {
      Navigator.of(context).removeRoute(route, count);
    }
  }

  @override
  void dispose() {
    if (VoiceCapturePage._onRequest == _c.onVoiceRequest) VoiceCapturePage._onRequest = null;
    _lifecycle.dispose();
    _c.removeListener(_onChange);
    // close() cancels the engine; dispose() alone would leave it listening.
    unawaited(_c.close());
    _c.dispose();
    _countdown.dispose();
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // VoiceOver or Switch Control: no timed save, no closing on silence.
    _c.accessible = MediaQuery.accessibleNavigationOf(context);
    final s = S.of(context);
    final t = Theme.of(context);
    final phase = _c.phase;
    final preview = _c.preview;
    final showPreview =
        preview != null &&
        (phase == VoicePhase.listening || phase == VoicePhase.preview || phase == VoicePhase.editing);
    return PopScope(
      canPop: false,
      // The back gesture closes the same way as the close button.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_c.close());
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Outside the scroll view: the close button is always visible.
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('voice-close'),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: s.close,
                      onPressed: () => unawaited(_c.close()),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(s.voiceTitle, textAlign: TextAlign.end, style: t.textTheme.titleMedium),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: ContentWidth(
                    maxWidth: 560,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_micPhases.contains(phase)) ...[_micArea(s, phase), const SizedBox(height: 16)],
                        ?_status(s, phase),
                        if (_c.transcript.isNotEmpty &&
                            (phase == VoicePhase.listening || phase == VoicePhase.preview)) ...[
                          const SizedBox(height: 16),
                          Semantics(
                            key: const Key('voice-transcript'),
                            container: true,
                            // Not a live region: VoiceOver reading the words
                            // aloud would reach the microphone.
                            child: Text(
                              _c.transcript,
                              textAlign: TextAlign.center,
                              style: t.textTheme.titleLarge?.copyWith(color: t.colorScheme.onSurface),
                            ),
                          ),
                        ],
                        if (phase == VoicePhase.editing) ...[
                          const SizedBox(height: 16),
                          TextField(
                            key: const Key('voice-draft'),
                            controller: _draft,
                            autofocus: true,
                            minLines: 1,
                            maxLines: 4,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.done,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(hintText: s.voiceDraftHint),
                            onChanged: _c.updateDraft,
                            onSubmitted: (_) => unawaited(_c.saveNow()),
                          ),
                        ],
                        if (showPreview) ...[
                          const SizedBox(height: 16),
                          _PreviewCard(
                            preview: preview,
                            now: _c.app.now(),
                            // Read out once when the utterance ends.
                            announce: phase == VoicePhase.preview,
                          ),
                        ],
                        if (phase == VoicePhase.preview && !preview!.isNote) ...[
                          const SizedBox(height: 16),
                          // The lists can change (or go) while the preview waits.
                          ListenableBuilder(listenable: _c.app, builder: (context, _) => _picker(s)),
                        ],
                        if (phase == VoicePhase.preview) ...[const SizedBox(height: 16), _previewActions(s)],
                        if (phase == VoicePhase.editing) ...[
                          const SizedBox(height: 16),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: FilledButton(
                              key: const Key('voice-save'),
                              onPressed: preview != null && preview.title.trim().isNotEmpty
                                  ? () => unawaited(_c.saveNow())
                                  : null,
                              child: Text(s.save),
                            ),
                          ),
                        ],
                        if (_c.saved.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Semantics(header: true, child: SectionHeader(s.voiceAdded)),
                          for (final item in _c.saved)
                            _SavedRow(
                              key: Key('voice-saved-${item.id}'),
                              item: item,
                              now: _c.app.now(),
                              onUndo: () => _c.undo(item),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The microphone button inside the level ring; with Reduce Motion the
  /// ring stays still and a stepped bar shows the level instead.
  Widget _micArea(S s, VoicePhase phase) {
    final c = Theme.of(context).colorScheme;
    final reduceMotion = reduceMotionOf(context);
    final listening = phase == VoicePhase.listening;
    return Column(
      children: [
        SizedBox.square(
          dimension: 128,
          child: Stack(
            alignment: Alignment.center,
            children: [
              RepaintBoundary(
                child: AnimatedScale(
                  // The only thing on the screen that moves with the voice.
                  scale: reduceMotion ? 1 : 1 + 0.15 * _c.level,
                  duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  child: Container(
                    key: const Key('voice-ring'),
                    width: 108,
                    height: 108,
                    // The soft fill alone is 1.1:1 on the surface; the primary
                    // edge keeps the ring visible (>= 3:1 in both themes).
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.primaryContainer,
                      border: Border.all(color: c.primary, width: 2),
                    ),
                  ),
                ),
              ),
              IconButton.filled(
                key: const Key('voice-mic'),
                style: IconButton.styleFrom(
                  backgroundColor: c.primary,
                  foregroundColor: c.onPrimary,
                  fixedSize: const Size.square(88),
                  iconSize: 40,
                ),
                icon: Icon(listening ? Icons.mic_rounded : Icons.mic_none_rounded),
                tooltip: listening ? s.voiceStopListening : s.voiceStartListening,
                onPressed: _micActivePhases.contains(phase) ? _c.toggleMic : null,
              ),
            ],
          ),
        ),
        if (reduceMotion) ...[const SizedBox(height: 12), _LevelBar(level: _c.level)],
      ],
    );
  }

  /// Icon and text for the phase; it changes only when the phase does, and
  /// is the live region VoiceOver announces, except while the microphone is
  /// about to open or open: VoiceOver's voice would reach the recogniser
  /// (compliance §4.1, accessibility 3).
  Widget? _status(S s, VoicePhase phase) {
    final status = switch (phase) {
      VoicePhase.preparing => (Icons.hourglass_top_rounded, s.voicePreparing, null),
      VoicePhase.listening => (Icons.graphic_eq_rounded, s.voiceListening, null),
      VoicePhase.saved => (Icons.check_circle_rounded, s.voiceSaved, null),
      VoicePhase.paused => (Icons.pause_circle_rounded, s.voicePaused, s.voiceTapToContinue),
      VoicePhase.error => (Icons.error_outline_rounded, s.voiceErrorGeneric, null),
      VoicePhase.permissionDenied => (Icons.mic_off_rounded, s.voicePermissionDenied, null),
      VoicePhase.dictationOff => (Icons.keyboard_voice_rounded, s.voiceDictationOff, null),
      VoicePhase.unsupportedLocale => (Icons.translate_rounded, s.voiceUnsupportedLocale, null),
      VoicePhase.unsupportedPlatform => (Icons.phonelink_off_rounded, s.voiceUnsupportedPlatform, null),
      // The preview card and the draft speak for themselves.
      VoicePhase.preview || VoicePhase.editing || VoicePhase.closed => null,
    };
    if (status == null) return null;
    final (icon, text, detail) = status;
    final t = Theme.of(context);
    final c = t.colorScheme;

    if (_errorPhases.contains(phase)) {
      final line = Semantics(
        key: const Key('voice-status'),
        container: true,
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: c.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text, style: t.textTheme.bodyLarge?.copyWith(color: c.onErrorContainer)),
            ),
          ],
        ),
      );
      final action = switch (phase) {
        VoicePhase.error => FilledButton(
          key: const Key('voice-retry'),
          onPressed: _c.toggleMic,
          child: Text(s.voiceRetry),
        ),
        // The only way back after a refusal; the system prompt is not shown again.
        VoicePhase.permissionDenied => FilledButton(
          key: const Key('voice-open-settings'),
          onPressed: () => unawaited(openAppSettings()),
          child: Text(s.openSettings),
        ),
        _ => null,
      };
      return SoftCard(
        color: c.errorContainer,
        shadow: false,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            line,
            if (action != null) ...[
              const SizedBox(height: 16),
              Align(alignment: AlignmentDirectional.centerStart, child: action),
            ],
          ],
        ),
      );
    }

    return Semantics(
      key: const Key('voice-status'),
      container: true,
      liveRegion: phase != VoicePhase.listening && phase != VoicePhase.preparing,
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: phase == VoicePhase.listening ? c.primary : c.onSurfaceVariant),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: t.textTheme.titleMedium?.copyWith(color: c.onSurface),
                ),
              ),
            ],
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: t.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  /// Under the preview of a task: "List", its chips in one row that scrolls
  /// sideways (the selected one first; a tap saves to it at once), and "Box",
  /// the four boxes two by two (a tap selects one).
  Widget _picker(S s) {
    final t = Theme.of(context);
    final selectedList = _c.listId;
    final selectedBox = _c.quadrant;
    final lists = [
      ..._c.app.lists.where((l) => l.id == selectedList),
      ..._c.app.lists.where((l) => l.id != selectedList),
    ];
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(text, style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        label(s.list),
        SingleChildScrollView(
          key: const Key('voice-list-row'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final l in lists)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: _PickChip(
                    key: Key('voice-list-${l.id}'),
                    label: l.name,
                    selected: l.id == selectedList,
                    // A long name is cut; VoiceOver reads it whole.
                    maxWidth: 240,
                    maxLines: 1,
                    onTap: () => unawaited(_c.pickList(l.id)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        label(s.box),
        LayoutBuilder(
          builder: (context, box) {
            const gap = 8.0;
            final width = (box.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final q in Quadrant.values)
                  SizedBox(
                    width: width,
                    child: _PickChip(
                      key: Key('voice-box-${q.name}'),
                      label: s.quadrantTitle(q),
                      selected: q == selectedBox,
                      onTap: () {
                        _c.pickQuadrant(q);
                        // The controller's countdown started again.
                        if (_c.previewOnTimer) _countdown.forward(from: 0);
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// Under the preview: the countdown while it is saved on a timer, then
  /// "Fix" and "Add" (with the selected list and box).
  Widget _previewActions(S s) {
    final buttons = Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        OutlinedButton(key: const Key('voice-fix'), onPressed: _c.edit, child: Text(s.voiceFix)),
        FilledButton(key: const Key('voice-save'), onPressed: () => unawaited(_c.saveNow()), child: Text(s.add)),
      ],
    );
    if (!_timedPreview || _c.accessible) return buttons;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Countdown(animation: _countdown, label: s.voiceCountdown),
        const SizedBox(height: 12),
        buttons,
      ],
    );
  }
}

/// The bar and the seconds left before the preview is saved. The bar is
/// hidden from VoiceOver (no value, no announcement every second).
class _Countdown extends StatelessWidget {
  const _Countdown({required this.animation, required this.label});

  final Animation<double> animation;
  final String Function(int seconds) label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final reduceMotion = reduceMotionOf(context);
    final total = VoiceTimings.previewHold.inMilliseconds;
    return Semantics(
      key: const Key('voice-countdown'),
      container: true,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final left = total * (1 - animation.value);
          final seconds = math.max(1, (left / 1000).ceil());
          return Row(
            children: [
              Expanded(
                child: ExcludeSemantics(
                  child: LinearProgressIndicator(
                    // With Reduce Motion the bar steps once a second.
                    value: (reduceMotion ? seconds * 1000 : left) / total,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                    color: c.primary,
                    backgroundColor: c.primaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(label(seconds), style: t.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
            ],
          );
        },
      ),
    );
  }
}

/// The parsed task as chips and a title, read by VoiceOver as one element:
/// "Annemi ara, Yarın 19:00, hatırlatma açık".
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview, required this.now, required this.announce});

  final SpokenTask preview;
  final DateTime now;

  /// Make it a live region, so it is read out once when it appears.
  final bool announce;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final p = preview;
    final due = p.due;
    final chips = <Widget>[
      if (p.isNote)
        _Chip(icon: Icons.sticky_note_2_outlined, label: s.voiceNoteChip)
      else if (due == null)
        _Chip(icon: Icons.event_busy_rounded, label: p.remind ? s.voiceUndatedRemindHint : s.someday)
      else ...[
        _Chip(
          icon: Icons.event_rounded,
          label: formatWhen(s, due, now: now, withTime: false),
        ),
        if (p.hasTime) _Chip(icon: Icons.schedule_rounded, label: p.ambiguousHour ? '${hhmm(due)} ?' : hhmm(due)),
        if (p.hasTime || p.remind) const _Chip(icon: Icons.notifications_rounded),
      ],
    ];
    return Semantics(
      key: const Key('voice-preview'),
      container: true,
      liveRegion: announce,
      label: _label(s),
      child: ExcludeSemantics(
        child: SoftCard(
          shadow: false,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: chips),
              if (p.title.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(p.title, style: t.textTheme.titleMedium?.copyWith(color: t.colorScheme.onSurface)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _label(S s) {
    final p = preview;
    final due = p.due;
    final parts = <String>[if (p.title.trim().isNotEmpty) p.title];
    if (p.isNote) {
      parts.add(s.voiceNoteChip);
    } else if (due == null) {
      // The hint's "·" only separates visually; read it as a pause.
      parts.add(p.remind ? s.voiceUndatedRemindHint.replaceAll(' · ', ', ') : s.someday);
    } else {
      final day = formatWhen(s, due, now: now, withTime: false);
      parts.add(p.hasTime ? '$day ${hhmm(due)}' : day);
      if (p.hasTime || p.remind) parts.add(s.voiceReminderOn);
      // Said instead of the "?" on the time chip.
      if (p.hasTime && p.ambiguousHour) parts.add(s.voiceTimeGuess);
    }
    return parts.join(', ');
  }
}

/// A preview chip with the look of a selected [SoftChip]; its text wraps at
/// large text sizes, and it can be an icon alone.
class _Chip extends StatelessWidget {
  const _Chip({required this.icon, this.label});

  final IconData icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final label = this.label;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.primaryContainer, borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: c.onPrimaryContainer),
            if (label != null) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(label, style: t.textTheme.labelLarge?.copyWith(color: c.onPrimaryContainer)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A list or box choice under the preview: at least 44 pt each way, read by
/// VoiceOver as a button with its whole name and whether it is selected; the
/// selection shows as a tick and a filled colour, not by colour alone.
class _PickChip extends StatelessWidget {
  const _PickChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.maxWidth = double.infinity,
    this.maxLines = 3,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double maxWidth;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final fg = selected ? c.onPrimaryContainer : c.onSurfaceVariant;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: selected ? c.primary : c.outline),
    );
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: 44, minHeight: 44, maxWidth: maxWidth),
        child: Material(
          color: selected ? c.primaryContainer : c.surfaceContainer,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[Icon(Icons.check_rounded, size: 18, color: fg), const SizedBox(width: 6)],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: maxLines,
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

/// One entry under "Added": what was saved, when it is due, the list it went
/// to, and undo.
class _SavedRow extends StatelessWidget {
  const _SavedRow({super.key, required this.item, required this.now, required this.onUndo});

  final SavedItem item;
  final DateTime now;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final due = item.due;
    final when = item.isNote
        ? s.voiceNoteChip
        : due == null
        ? s.someday
        : formatWhen(s, due, now: now, withTime: item.hasTime);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, end: 12),
            child: Icon(Icons.check_circle_rounded, color: c.tertiary),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: item.title,
                    children: [
                      TextSpan(
                        text: ' · $when',
                        style: TextStyle(color: c.onSurfaceVariant),
                      ),
                    ],
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodyLarge?.copyWith(color: c.onSurface),
                ),
                if (item.listName case final list?)
                  Text(s.voiceSavedTo(list), style: t.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
                if (item.inBackground)
                  Text(s.voiceSavedOnLock, style: t.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: Key('voice-undo-${item.id}'),
            icon: const Icon(Icons.undo_rounded),
            tooltip: item.isNote ? s.voiceUndoNote(_short(item.title)) : s.voiceUndoItem(_short(item.title)),
            onPressed: onUndo,
          ),
        ],
      ),
    );
  }
}

/// [text] on one line and at most 60 characters, for a button's label: a
/// 600-character title would fill the screen as a tooltip.
String _short(String text) {
  final line = text.replaceAll(RegExp(r'\s+'), ' ').trim().characters;
  return line.length <= 60 ? line.string : '${line.take(59).string.trimRight()}…';
}

/// The input level in five still steps, for Reduce Motion. Visual only.
class _LevelBar extends StatelessWidget {
  const _LevelBar({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final lit = (level * 5).ceil().clamp(0, 5);
    return ExcludeSemantics(
      child: Row(
        key: const Key('voice-level-bar'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 5; i++)
            Container(
              width: 16,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: i < lit ? c.primary : c.outlineVariant,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }
}
