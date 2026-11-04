import 'package:flutter/material.dart';

import '../../core/turkish_text.dart';
import '../../l10n/strings.dart';
import '../../theme/pamnot_theme.dart';

/// 'monospace' only resolves on Android; these cover Apple, Windows and Linux.
const monoFallback = ['Menlo', 'SF Mono', 'Consolas', 'Courier New', 'DejaVu Sans Mono', 'monospace'];

/// Opens a collaboration sheet the way the app opens its editors.
Future<T?> showCloudSheet<T>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: builder,
    );

/// Title plus scrolling body, padded for the keyboard.
class CloudSheetBody extends StatelessWidget {
  const CloudSheetBody({super.key, required this.title, required this.children, this.icon});

  final String title;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
        children: [
          Row(
            children: [
              if (icon != null) ...[Icon(icon, color: t.colorScheme.primary), const SizedBox(width: 10)],
              Expanded(child: Text(title, style: t.textTheme.titleLarge)),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

enum NoticeTone { info, warning, error, success }

/// A soft rounded note: explanations, warnings and errors.
class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.tone = NoticeTone.info, this.action});

  final String text;
  final NoticeTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final (bg, fg, icon) = switch (tone) {
      NoticeTone.info => (c.primaryContainer, c.onPrimaryContainer, Icons.info_outline_rounded),
      NoticeTone.warning => (c.secondaryContainer, c.onSecondaryContainer, Icons.warning_amber_rounded),
      NoticeTone.error => (c.errorContainer, c.onErrorContainer, Icons.error_outline_rounded),
      NoticeTone.success => (c.tertiaryContainer, c.onTertiaryContainer, Icons.check_circle_outline_rounded),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: t.textTheme.bodyMedium?.copyWith(color: fg))),
            ],
          ),
          if (action != null) Align(alignment: AlignmentDirectional.centerEnd, child: action),
        ],
      ),
    );
  }
}

/// A row with a small spinner, for "Bağlanıyor…" style progress.
class BusyLine extends StatelessWidget {
  const BusyLine(this.text, {super.key, this.done = false, this.value});

  final String text;
  final bool done;

  /// Determinate progress 0…1, or null.
  final double? value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: done
                ? Icon(Icons.check_circle_rounded, size: 20, color: t.colorScheme.tertiary)
                : CircularProgressIndicator(strokeWidth: 2.4, value: value),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: t.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

/// A person's circle: pastel paper, accent ring, initial (Turkish casing).
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, required this.colorIndex, this.size = 36, this.online = false});

  final String name;
  final int colorIndex;
  final double size;
  final bool online;

  static String initialOf(String name) {
    final n = name.trim();
    if (n.isEmpty) return '?';
    return upper(n.characters.first, turkish: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = pastelAt(colorIndex);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.paper(t.brightness),
            shape: BoxShape.circle,
            border: Border.all(color: p.accent, width: 2),
          ),
          child: Text(
            initialOf(name),
            style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: t.colorScheme.onSurface),
          ),
        ),
        if (online)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: size * 0.32,
              height: size * 0.32,
              decoration: BoxDecoration(
                color: t.colorScheme.tertiary,
                shape: BoxShape.circle,
                border: Border.all(color: t.colorScheme.surfaceContainerLow, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

/// Yes/no dialog; true only when confirmed.
Future<bool> confirmCloudAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
  bool destructive = false,
}) async {
  final s = S.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      final c = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
          FilledButton(
            style: destructive ? FilledButton.styleFrom(backgroundColor: c.error, foregroundColor: c.onError) : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirm),
          ),
        ],
      );
    },
  );
  return ok == true;
}

void showCloudSnack(BuildContext context, String text) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
}
