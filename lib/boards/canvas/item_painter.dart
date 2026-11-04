import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/turkish_text.dart';
import '../../l10n/strings.dart';
import '../../theme/pamnot_theme.dart';
import '../model/board_item.dart';
import 'board_text.dart';
import 'canvas_strings.dart';
import 'ink_layer.dart';
import 'lanes.dart';
import 'scene.dart';

/// Theme colours for the painters. Painters compare palettes in
/// shouldRepaint, so a theme switch repaints (and re-records) once.
@immutable
class BoardPalette {
  const BoardPalette({
    required this.brightness,
    required this.background,
    required this.grid,
    required this.card,
    required this.cardBorder,
    required this.text,
    required this.muted,
    required this.primary,
    required this.done,
    required this.overdueBg,
    required this.overdueText,
    required this.chip,
    required this.shadow,
    required this.halo,
  });

  factory BoardPalette.of(ThemeData t) {
    final c = t.colorScheme;
    final dark = t.brightness == Brightness.dark;
    return BoardPalette(
      brightness: t.brightness,
      background: c.surface,
      grid: c.primary.withValues(alpha: dark ? 0.26 : 0.22),
      card: c.surfaceContainerLowest,
      cardBorder: c.outlineVariant,
      text: c.onSurface,
      muted: c.onSurfaceVariant,
      primary: c.primary,
      done: c.tertiary,
      overdueBg: c.errorContainer,
      overdueText: c.onErrorContainer,
      chip: c.surfaceContainer,
      shadow: c.shadow.withValues(alpha: dark ? 0.32 : 0.07),
      halo: c.surfaceContainerLowest,
    );
  }

  final Brightness brightness;
  final Color background;
  final Color grid;
  final Color card;
  final Color cardBorder;
  final Color text;
  final Color muted;
  final Color primary;
  final Color done;
  final Color overdueBg;
  final Color overdueText;
  final Color chip;

  /// A crisp offset shape under raised items (no blur on the canvas).
  final Color shadow;

  /// Outline around presence arrows.
  final Color halo;

  Color lanePaper(int i) => pastelAt(i).paper(brightness);
  Color accent(int i) => pastelAt(i).accent;

  /// Stickies are a step deeper than the lane tint so they read on any lane.
  Color sticky(int i) {
    final p = pastelAt(i);
    return brightness == Brightness.dark ? Color.lerp(p.dark, p.accent, 0.30)! : Color.lerp(p.light, p.accent, 0.40)!;
  }

  @override
  bool operator ==(Object other) =>
      other is BoardPalette &&
      other.brightness == brightness &&
      other.background == background &&
      other.grid == grid &&
      other.card == card &&
      other.cardBorder == cardBorder &&
      other.text == text &&
      other.muted == muted &&
      other.primary == primary &&
      other.done == done &&
      other.overdueBg == overdueBg &&
      other.overdueText == overdueText &&
      other.chip == chip &&
      other.shadow == shadow &&
      other.halo == halo;

  @override
  int get hashCode => Object.hash(
    brightness,
    background,
    grid,
    card,
    cardBorder,
    text,
    muted,
    primary,
    done,
    overdueBg,
    overdueText,
    chip,
    shadow,
    halo,
  );
}

/// Initials and colour of a card's assignee, when known.
typedef AssigneeLook = (String initials, int colorIndex)? Function(String userId);

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = String.fromCharCode(parts.first.runes.first);
  final second = parts.length > 1 ? String.fromCharCode(parts.last.runes.first) : '';
  return upper(first + second, turkish: true);
}

/// Draws lanes, cards, stickies and ink in canvas units at a level of
/// detail. Holds reusable paints; text comes from [BoardTextCache].
class BoardItemPainter {
  BoardItemPainter({
    required this.palette,
    required this.text,
    required this.outlines,
    required this.strings,
    required this.now,
    this.assignee,
  });

  final BoardPalette palette;
  final BoardTextCache text;
  final InkOutlines outlines;
  final S strings;
  final DateTime Function() now;
  final AssigneeLook? assignee;

  final Paint _fill = Paint();
  final Paint _line = Paint()..style = PaintingStyle.stroke;
  final InkPaints _ink = InkPaints();

  /// Text below this many screen pixels is drawn as bars.
  static const minTextPx = 5.0;

  Color cardTitleColor(BoardItem card, bool done) => done || card.title.isEmpty ? palette.muted : palette.text;

  // ------------------------------------------------------------------ lanes

  void lane(Canvas c, Lane lane, BoardItem? column, int lod, double s) {
    final ci = column?.colorIndex ?? 0;
    final r = lane.rect;
    _fill.color = palette.lanePaper(ci);
    if (lod == 0) {
      c.drawRect(r, _fill);
      return;
    }
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(LaneMetrics.radius));
    c.drawRRect(rr, _fill);
    _line
      ..color = palette.accent(ci).withValues(alpha: lod == 2 ? 0.45 : 0.3)
      ..strokeWidth = lod == 2 ? 1.2 : 2;
    c.drawRRect(rr, _line);
    _fill.color = palette.accent(ci);
    c.drawCircle(Offset(r.left + 24, r.top + 27), 5.5, _fill);
    final title = column?.title ?? '';
    final x = r.left + 38, maxW = r.width - 38 - 52;
    if (lod == 2 && 16 * s >= minTextPx) {
      final tp = text.obtain(
        'l:${lane.columnId}',
        title,
        16,
        palette.text,
        () =>
            boardPainter(title, boardText(16, palette.text, weight: FontWeight.w800), maxLines: 1)
              ..layout(maxWidth: maxW),
      );
      if (tp != null) {
        tp.paint(c, Offset(x, r.top + 27 - tp.height / 2));
      } else {
        _greek(c, x, r.top + 17, estimateLines(title, 16, maxW, maxLines: 1), 16, palette.text);
      }
      final count = '${lane.cards.length}';
      final np = text.obtain(
        'n:${lane.columnId}',
        count,
        14,
        palette.muted,
        () => boardPainter(count, boardText(14, palette.muted, weight: FontWeight.w700))..layout(),
      );
      if (np != null) np.paint(c, Offset(r.right - 20 - np.width, r.top + 27 - np.height / 2));
      if (column?.isDone ?? false) {
        _icon(c, Icons.check_circle_rounded, 16, palette.done, Offset(r.right - 46, r.top + 19));
      }
    } else {
      _greek(c, x, r.top + 17, estimateLines(title, 16, maxW, maxLines: 1), 16, palette.text);
    }
  }

  // ------------------------------------------------------------------ cards

  void card(Canvas c, SceneItem si, Rect r, int lod, double s, {String placeholder = ''}) {
    final it = si.item;
    _fill.color = palette.card;
    if (lod == 0) {
      c.drawRect(r, _fill);
      return;
    }
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(CardGeometry.radius));
    c.drawRRect(rr, _fill);
    if (lod == 2) {
      _line
        ..color = palette.cardBorder
        ..strokeWidth = 1;
      c.drawRRect(rr, _line);
    }
    // Colour accent: a soft pill inside the left edge (no clipping needed).
    _fill.color = palette.accent(it.colorIndex);
    c.drawRRect(RRect.fromLTRBR(r.left + 7, r.top + 11, r.left + 11, r.bottom - 11, const Radius.circular(2)), _fill);

    final tx = r.left + CardGeometry.padLeft, ty = r.top + CardGeometry.padV;
    final color = cardTitleColor(it, si.done);
    if (lod == 2 && CardGeometry.titleSize * s >= minTextPx) {
      final title = it.title.isEmpty ? placeholder : it.title;
      final tp = text.obtain(
        'c:${si.id}',
        title,
        CardGeometry.titleSize,
        color,
        () =>
            boardPainter(title, cardTitleStyle(color), maxLines: CardGeometry.titleLines)
              ..layout(maxWidth: CardGeometry.titleWidth(si.done)),
      );
      if (tp != null) {
        tp.paint(c, Offset(tx, ty));
      } else {
        _greek(c, tx, ty, si.lines, CardGeometry.titleSize, color);
      }
      if (si.done) {
        _icon(
          c,
          Icons.check_circle_rounded,
          CardGeometry.doneIcon,
          palette.done,
          Offset(r.right - CardGeometry.padRight - CardGeometry.doneIcon, ty + 1),
        );
      }
      if (si.hasMeta) _meta(c, si, r);
    } else {
      _greek(c, tx, ty, si.lines, CardGeometry.titleSize, color);
      if (si.hasMeta) {
        _fill.color = palette.muted.withValues(alpha: 0.18);
        c.drawRRect(
          RRect.fromLTRBR(
            tx,
            r.bottom - CardGeometry.padV - CardGeometry.metaHeight,
            tx + 64,
            r.bottom - CardGeometry.padV,
            const Radius.circular(8),
          ),
          _fill,
        );
      }
    }
  }

  void _meta(Canvas c, SceneItem si, Rect r) {
    final it = si.item;
    final top = r.bottom - CardGeometry.padV - CardGeometry.metaHeight;
    final mid = top + CardGeometry.metaHeight / 2;
    var x = r.left + CardGeometry.padLeft;
    final due = it.dueDate;
    if (due != null) {
      final today = now();
      final overdue = !si.done && due.isBefore(DateTime(today.year, today.month, today.day));
      final label = overdue ? strings.canvasOverdue(_day(due)) : _day(due);
      final fg = overdue ? palette.overdueText : palette.muted;
      final tp = text.obtain(
        'd:${si.id}',
        label,
        12,
        fg,
        () => boardPainter(label, boardText(12, fg, weight: FontWeight.w700), strut: false)..layout(),
        force: true,
      )!;
      final w = 8 + 14 + 4 + tp.width + 8;
      _fill.color = overdue ? palette.overdueBg : palette.chip;
      c.drawRRect(RRect.fromLTRBR(x, top, x + w, top + CardGeometry.metaHeight, const Radius.circular(8)), _fill);
      _icon(c, Icons.event_rounded, 14, fg, Offset(x + 7, mid - 7));
      tp.paint(c, Offset(x + 8 + 14 + 4, mid - tp.height / 2));
      x += w + 8;
    }
    final subs = it.subtasks;
    if (subs.isNotEmpty) {
      final label = '${subs.where((t) => t.done).length}/${subs.length}';
      final tp = text.obtain(
        'k:${si.id}',
        label,
        12,
        palette.muted,
        () => boardPainter(label, boardText(12, palette.muted, weight: FontWeight.w700), strut: false)..layout(),
        force: true,
      )!;
      _icon(c, Icons.check_box_outlined, 15, palette.muted, Offset(x, mid - 7.5));
      tp.paint(c, Offset(x + 18, mid - tp.height / 2));
      x += 18 + tp.width + 10;
    }
    if (it.notes.isNotEmpty) {
      _icon(c, Icons.notes_rounded, 15, palette.muted, Offset(x, mid - 7.5));
    }
    final who = it.assigneeId;
    if (who != null) {
      final look = assignee?.call(who);
      final center = Offset(r.right - CardGeometry.padRight - 11, mid);
      _fill.color = look == null ? palette.chip : pastelAt(look.$2).paper(palette.brightness);
      c.drawCircle(center, 11, _fill);
      _line
        ..color = look == null ? palette.cardBorder : palette.accent(look.$2)
        ..strokeWidth = 1.5;
      c.drawCircle(center, 11, _line);
      if (look == null) {
        _icon(c, Icons.person_rounded, 14, palette.muted, center - const Offset(7, 7));
      } else {
        final tp = text.obtain(
          'a:${si.id}',
          look.$1,
          10,
          palette.text,
          () => boardPainter(look.$1, boardText(10, palette.text, weight: FontWeight.w800), strut: false)..layout(),
          force: true,
        )!;
        tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  String _day(DateTime d) {
    try {
      return DateFormat('d MMM', strings.locale).format(d);
    } catch (_) {
      // Date symbols not initialised (tests, very early frames).
      return '${d.day}.${d.month}';
    }
  }

  // --------------------------------------------------------------- stickies

  void sticky(Canvas c, SceneItem si, Rect r, int lod, double s, {bool hideText = false, bool raised = false}) {
    final it = si.item;
    _fill.color = palette.sticky(it.colorIndex);
    if (lod == 0) {
      c.drawRect(r, _fill);
      return;
    }
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(StickyMetrics.radius));
    if (lod == 2 || raised) {
      final fill = _fill.color;
      _fill.color = palette.shadow;
      c.drawRRect(rr.shift(Offset(0, raised ? 8 : 3)), _fill);
      _fill.color = fill;
    }
    c.drawRRect(rr, _fill);
    final txt = it.text;
    if (hideText || txt.isEmpty) return;
    final origin = Offset(r.left + StickyMetrics.pad, r.top + StickyMetrics.pad);
    if (lod == 2) {
      if (si.fitText != txt) {
        text.spend(() {
          final (f, tp) = fitStickyText(txt, palette.text);
          si
            ..fit = f
            ..fitText = txt;
          text.put('s:${si.id}', txt, f, palette.text, tp);
        });
      }
      if (si.fitText == txt) {
        if (si.fit * s < minTextPx) {
          _greek(
            c,
            origin.dx,
            origin.dy,
            estimateLines(txt, si.fit, StickyMetrics.inner),
            si.fit,
            palette.text,
            maxHeight: StickyMetrics.inner,
          );
          return;
        }
        final tp = text.obtain(
          's:${si.id}',
          txt,
          si.fit,
          palette.text,
          () => stickyPainterAt(txt, si.fit, palette.text),
        );
        if (tp != null) {
          tp.paint(c, origin);
          return;
        }
      }
    }
    final f = si.fitText == txt ? si.fit : estimateStickyFont(txt);
    _greek(
      c,
      origin.dx,
      origin.dy,
      estimateLines(txt, f, StickyMetrics.inner),
      f,
      palette.text,
      maxHeight: StickyMetrics.inner,
    );
  }

  // -------------------------------------------------------------------- ink

  void ink(Canvas c, SceneItem si, Offset origin) {
    final s = si.stroke;
    if (s == null) return;
    paintInk(c, s, si.polyline, origin, outlines, _ink);
  }

  // ---------------------------------------------------------------- helpers

  /// Bars where text would be: cheap and calm at overview zoom.
  void _greek(Canvas c, double x, double y, List<double> lines, double f, Color color, {double? maxHeight}) {
    _fill.color = color.withValues(alpha: 0.25);
    final lh = 1.3 * f, bh = 0.55 * f;
    for (var i = 0; i < lines.length; i++) {
      if (maxHeight != null && (i + 1) * lh > maxHeight + 0.5) break;
      final w = lines[i];
      if (w <= 0) continue;
      c.drawRect(Rect.fromLTWH(x, y + i * lh + (lh - bh) / 2, w, bh), _fill);
    }
  }

  void _icon(Canvas c, IconData icon, double size, Color color, Offset at) {
    final glyph = String.fromCharCode(icon.codePoint);
    final tp = text.obtain(
      'i:${icon.codePoint}:$size',
      glyph,
      size,
      color,
      () => TextPainter(
        text: TextSpan(
          text: glyph,
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: size,
            color: color,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout(),
      force: true,
    )!;
    tp.paint(c, at);
  }
}

/// A sticky's text laid out at a fitted size [f].
TextPainter stickyPainterAt(String text, double f, Color color) {
  final lines = (StickyMetrics.inner / (1.3 * f)).floor();
  final tp = boardPainter(text, boardText(f, color), maxLines: lines < 1 ? 1 : lines)
    ..layout(maxWidth: StickyMetrics.inner);
  return tp;
}
