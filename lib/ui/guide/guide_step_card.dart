import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../common/soft.dart';
import 'phone_hand_animation.dart';

/// One step of the "Shortcuts & Siri" guide: its title and a "To do" / "Done"
/// badge (icon and text, never colour alone); a tap opens the drawing, the
/// numbered lines and the step's [actions].
///
/// The header carries `Key('guide-step-<step>')`.
class GuideStepCard extends StatefulWidget {
  const GuideStepCard({
    super.key,
    required this.step,
    required this.scene,
    required this.done,
    required this.lines,
    this.actions = const [],
    this.onOpen,
    this.onClose,
  });

  /// One of `AppSettings.guideSteps`.
  final String step;
  final GuideScene scene;
  final bool done;
  final List<String> lines;

  /// Buttons under the lines, stacked full width.
  final List<Widget> actions;

  /// Called each time the card is opened.
  final VoidCallback? onOpen;

  /// Called each time the card is closed.
  final VoidCallback? onClose;

  @override
  State<GuideStepCard> createState() => _GuideStepCardState();
}

class _GuideStepCardState extends State<GuideStepCard> {
  bool _open = false;

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      widget.onOpen?.call();
    } else {
      widget.onClose?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final title = s.guideStepTitle(widget.step);

    final header = Semantics(
      button: true,
      expanded: _open,
      child: InkWell(
        key: Key('guide-step-${widget.step}'),
        onTap: _toggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
            child: Row(
              children: [
                Expanded(child: Text(title, style: t.textTheme.titleMedium)),
                const SizedBox(width: 8),
                Flexible(child: _Badge(done: widget.done)),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: motion(context, const Duration(milliseconds: 200)),
                  child: Icon(Icons.expand_more_rounded, color: c.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 160,
            child: PhoneHandAnimation(
              scene: widget.scene,
              // A still frame, the hand resting on the target, for less motion.
              progress: reduceMotionOf(context) ? 1 : null,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < widget.lines.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: MergeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i + 1}.', style: t.textTheme.bodyLarge?.copyWith(color: c.primary)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(widget.lines[i], style: t.textTheme.bodyLarge)),
                  ],
                ),
              ),
            ),
          for (final a in widget.actions) ...[const SizedBox(height: 8), a],
        ],
      ),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [header, if (_open) body],
    );
    return SoftCard(
      padding: EdgeInsets.zero,
      // With less motion the card opens at once (AnimatedSize cannot run
      // with a zero duration).
      child: reduceMotionOf(context)
          ? content
          : AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: content,
            ),
    );
  }
}

/// "To do" with an empty circle, or "Done" with a check.
class _Badge extends StatelessWidget {
  const _Badge({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final color = done ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked, size: 18, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            done ? s.guideDoneBadge : s.guideTodo,
            style: t.textTheme.labelLarge?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
