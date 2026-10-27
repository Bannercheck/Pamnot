import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/ink.dart';
import '../../models/note.dart';
import '../../theme/pamuk_theme.dart';
import '../common/format.dart';
import '../common/soft.dart';
import 'ink/ink_painter.dart';

class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.note, required this.now, this.onTap, this.onLongPress, this.compact = false});

  final Note note;
  final DateTime now;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Fixed-height variant for horizontal strips.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final p = pastelAt(note.colorIndex);
    final title = note.title.trim();
    final body = note.body.trim();
    return SoftCard(
      color: p.paper(t.brightness),
      onTap: onTap,
      onLongPress: onLongPress,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title.isEmpty ? (body.isEmpty && !note.hasInk ? s.untitled : (body.isEmpty ? s.newHandwriting : body.split('\n').first)) : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (note.pinned) Icon(Icons.push_pin_rounded, size: 16, color: p.accent),
            ],
          ),
          if (body.isNotEmpty && title.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              body,
              maxLines: compact ? 3 : 8,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.45),
            ),
          ],
          if (note.hasInk) ...[
            const SizedBox(height: 8),
            _InkPreview(strokes: note.ink, height: compact ? 70 : 120),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (note.hasInk) ...[
                Icon(Icons.draw_rounded, size: 14, color: p.accent),
                const SizedBox(width: 4),
              ],
              Text(
                formatWhen(s, note.updatedAt, now: now),
                style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InkPreview extends StatelessWidget {
  const _InkPreview({required this.strokes, required this.height});

  final List<InkStroke> strokes;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Crop to the written area so a note with a few words at the top
    // doesn't preview as an empty card.
    return LayoutBuilder(builder: (context, c) {
      final scale = c.maxWidth / kPageWidth;
      final contentH = (inkExtent(strokes) + 20) * scale;
      return SizedBox(
        height: contentH.clamp(24.0, height),
        width: double.infinity,
        child: RepaintBoundary(child: CustomPaint(painter: InkThumbnailPainter(strokes))),
      );
    });
  }
}
