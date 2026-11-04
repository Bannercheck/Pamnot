import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../l10n/strings.dart';
import '../../theme/pamnot_theme.dart';
import '../connection.dart';
import '../model/board_item.dart';
import 'board_text.dart';
import 'canvas_strings.dart';
import 'item_painter.dart';
import 'lanes.dart';
import 'retained_picture.dart';
import 'scene.dart';
import 'session.dart';
import 'viewport.dart';

/// Draws board content (lanes, cards, stickies, ink) in z-order, in canvas
/// units, skipping what the lifted layer owns. Shared by the detail painter
/// and the overview recording.
class WorldDrawer {
  WorldDrawer(this.session, this.palette, this.strings, {AssigneeLook? assignee})
    : items = BoardItemPainter(
        palette: palette,
        text: session.text,
        outlines: session.outlines,
        strings: strings,
        now: session.now,
        assignee: assignee,
      );

  final BoardSession session;
  final BoardPalette palette;
  final S strings;
  final BoardItemPainter items;

  /// Draws every item (overlapping [cull], when given) that the lifted
  /// layer doesn't own.
  void paintItems(Canvas canvas, {required int lod, required double scale, Rect? cull}) {
    final scene = session.scene;
    final lifted = session.lifted;
    final editor = session.editor;
    final placeholder = scene.placeholder;
    if (!lifted.lanes) {
      for (final lane in scene.lanes.lanes) {
        if (cull != null && !lane.rect.overlaps(cull)) continue;
        items.lane(canvas, lane, editor.item(lane.columnId), lod, scale);
        for (final lc in lane.cards) {
          if (cull != null) {
            if (lc.rect.top > cull.bottom) break;
            if (lc.rect.bottom < cull.top) continue;
          }
          if (lifted.hides(lc.id)) continue;
          final si = scene.byId(lc.id);
          if (si != null) items.card(canvas, si, lc.rect, lod, scale, placeholder: placeholder);
        }
      }
    }
    for (final si in scene.free) {
      if (cull != null && !si.bounds.overlaps(cull)) continue;
      if (lifted.hides(si.id)) continue;
      if (si.kind == ItemKind.sticky) {
        items.sticky(canvas, si, si.bounds, lod, scale);
      } else {
        items.ink(canvas, si, si.origin);
      }
    }
  }
}

/// The board at detail zoom (LOD 2), recorded every frame with a
/// brute-force cull: only what is on screen, with full text. Below detail
/// zoom it draws nothing and [BoardOverviewSource] takes over. No item
/// widgets, no blur, no saveLayer, no per-item clipping.
class BoardWorldPainter extends CustomPainter {
  BoardWorldPainter(this.session, this.palette, this.strings, {AssigneeLook? assignee})
    : drawer = WorldDrawer(session, palette, strings, assignee: assignee),
      super(
        repaint: Listenable.merge([session.viewport, session.scene, session.lifted, session.outlines, session.text]),
      );

  final BoardSession session;
  final BoardPalette palette;
  final S strings;
  final WorldDrawer drawer;

  @override
  void paint(Canvas canvas, Size size) {
    final vp = session.viewport;
    if (vp.lod != 2) return;
    session.text.beginFrame();
    canvas.save();
    canvas.transform(vp.matrix);
    drawer.paintItems(canvas, lod: 2, scale: vp.scale, cull: vp.visibleCanvasRect.inflate(4 / vp.scale));
    canvas.restore();
  }

  @override
  bool shouldRepaint(BoardWorldPainter old) =>
      old.session != session || old.palette != palette || old.strings != strings;
}

/// The whole board at overview zoom (LOD 1 and 0): one recording per level,
/// content and lifted set, shown through the viewport matrix by a
/// [RetainedPicture]. Rebuilt lazily; slow rebuilds are throttled.
class BoardOverviewSource implements RetainedPictureSource {
  BoardOverviewSource(this.session, this.palette, this.strings, {AssigneeLook? assignee})
    : drawer = WorldDrawer(session, palette, strings, assignee: assignee),
      repaint = Listenable.merge([session.viewport, session.scene, session.lifted, session.outlines]);

  final BoardSession session;
  final BoardPalette palette;
  final S strings;
  final WorldDrawer drawer;

  @override
  final Listenable repaint;

  @override
  Object? get key => (
    session.viewport.lod,
    session.scene.revision,
    session.lifted.membershipRevision,
    // Bumps once when the outline queue runs dry, not per built stroke.
    session.outlines.settledRevision,
    palette,
    strings,
  );

  @override
  Matrix4? get transform {
    final vp = session.viewport;
    return vp.lod == 2 ? null : Matrix4.fromFloat64List(vp.matrix);
  }

  @override
  bool get throttle => true;

  @override
  bool get releaseWhenHidden => false;

  @override
  void record(Canvas canvas) {
    final vp = session.viewport;
    drawer.paintItems(canvas, lod: vp.lod, scale: vp.scale);
  }
}

/// Dragged items (or the whole lane block) and the sticky being edited,
/// recorded once per lift and shown at the live delta: a drag frame moves a
/// transform, it records nothing.
class LiftedSource implements RetainedPictureSource {
  LiftedSource(this.session, this.palette, this.strings, {AssigneeLook? assignee})
    : _items = BoardItemPainter(
        palette: palette,
        text: session.text,
        outlines: session.outlines,
        strings: strings,
        now: session.now,
        assignee: assignee,
      ),
      repaint = Listenable.merge([session.viewport, session.lifted, session.scene]);

  final BoardSession session;
  final BoardPalette palette;
  final S strings;
  final BoardItemPainter _items;

  @override
  final Listenable repaint;

  @override
  Object? get key => (
    session.lifted.membershipRevision,
    session.lifted.raised,
    session.scene.revision,
    session.viewport.lod,
    palette,
    strings,
  );

  @override
  Matrix4? get transform {
    final lifted = session.lifted;
    if (lifted.isEmpty) return null;
    final d = lifted.delta;
    return Matrix4.fromFloat64List(session.viewport.matrix)..translateByDouble(d.dx, d.dy, 0, 1);
  }

  @override
  bool get throttle => false;

  @override
  bool get releaseWhenHidden => true;

  @override
  void record(Canvas c) {
    final scene = session.scene;
    final lifted = session.lifted;
    final lod = session.viewport.lod;
    final s = session.viewport.scale;
    final raised = lifted.raised;
    final shadow = Paint()..color = palette.shadow;
    if (lifted.lanes) {
      if (raised) {
        c.drawRRect(
          RRect.fromRectAndRadius(
            scene.lanes.bounds.shift(const Offset(0, 10)),
            const Radius.circular(LaneMetrics.radius),
          ),
          shadow,
        );
      }
      for (final lane in scene.lanes.lanes) {
        _items.lane(c, lane, session.editor.item(lane.columnId), lod, s);
        for (final lc in lane.cards) {
          final si = scene.byId(lc.id);
          if (si != null) _items.card(c, si, lc.rect, lod, s, placeholder: scene.placeholder);
        }
      }
    }
    // Keep z-order among lifted stickies and ink.
    for (final si in scene.free) {
      if (!lifted.contains(si.id)) continue;
      if (si.kind == ItemKind.sticky) {
        final editing = si.id == lifted.editing;
        _items.sticky(c, si, si.bounds, lod, s, hideText: editing, raised: raised && !editing);
      } else {
        _items.ink(c, si, si.origin);
      }
    }
    for (final si in scene.cards) {
      if (!lifted.ids.contains(si.id)) continue;
      if (raised) {
        c.drawRRect(
          RRect.fromRectAndRadius(si.bounds.shift(const Offset(0, 8)), const Radius.circular(CardGeometry.radius)),
          shadow,
        );
      }
      // A dragged card stays readable even at overview zoom.
      _items.card(c, si, si.bounds, math.max(lod, 1), s, placeholder: scene.placeholder);
    }
  }
}

/// The dot grid, in screen space with one drawRawPoints call: spacing
/// 40 · 2^k canvas units with the smallest k that keeps dots at least
/// 18 px apart (so always 18–36 px on screen), hidden when zoomed far out.
class GridPainter extends CustomPainter {
  GridPainter(this.viewport, this.color) : super(repaint: viewport);

  final BoardViewport viewport;
  final Color color;
  Float32List _buf = Float32List(0);

  static const hiddenBelow = 0.15;

  /// Spacing in canvas units at scale [s].
  static double spacingFor(double s) {
    var spacing = 40.0;
    while (spacing * s < 18) {
      spacing *= 2;
    }
    while (spacing / 2 * s >= 18) {
      spacing /= 2;
    }
    return spacing;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = viewport.scale;
    if (s < hiddenBelow || size.isEmpty) return;
    final px = spacingFor(s) * s;
    final fadeIn = ((s - hiddenBelow) / 0.05).clamp(0.0, 1.0);
    final density = ui.lerpDouble(0.55, 1.0, ((px - 18) / 18).clamp(0.0, 1.0))!;
    final alpha = color.a * fadeIn * density;
    if (alpha <= 0.01) return;
    final o = viewport.offset;
    final x0 = o.dx % px, y0 = o.dy % px;
    final cols = ((size.width - x0) / px).floor() + 1;
    final rows = ((size.height - y0) / px).floor() + 1;
    final n = cols * rows * 2;
    if (_buf.length < n) _buf = Float32List(n);
    var k = 0;
    for (var j = 0; j < rows; j++) {
      final y = y0 + j * px;
      for (var i = 0; i < cols; i++) {
        _buf[k++] = x0 + i * px;
        _buf[k++] = y;
      }
    }
    canvas.drawRawPoints(
      ui.PointMode.points,
      Float32List.sublistView(_buf, 0, k),
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(GridPainter old) => old.viewport != viewport || old.color != color;
}

/// Selection, hover, marquee, the card drop line, teammates' editing
/// outlines and the eraser ring, in screen space at constant line widths.
class OverlayPainter extends CustomPainter {
  OverlayPainter(this.session, this.palette, this.strings, this.peers)
    : super(
        repaint: Listenable.merge([
          session.viewport,
          session.selection,
          session.hover,
          session.marquee,
          session.drop,
          session.lifted,
          session.scene,
          session.eraserRing,
          peers,
        ]),
      );

  final BoardSession session;
  final BoardPalette palette;
  final S strings;
  final ValueListenable<List<Peer>> peers;

  Rect _screenOf(SceneItem si) {
    final lifted = session.lifted;
    var b = si.bounds;
    if (lifted.ids.contains(si.id) || (lifted.lanes && si.kind == ItemKind.card)) b = b.shift(lifted.delta);
    return session.viewport.rectToScreen(b);
  }

  static double _radius(SceneItem si, double s) => switch (si.kind) {
    ItemKind.card => CardGeometry.radius * s + 3,
    ItemKind.sticky => StickyMetrics.radius * s + 3,
    _ => 6,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final vp = session.viewport;
    final scene = session.scene;
    final s = vp.scale;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fill = Paint();

    final d = session.drop.value;
    if (d != null) {
      final lane = scene.lanes.laneById(d.columnId);
      if (lane != null) {
        final r = vp.rectToScreen(lane.rect);
        line
          ..color = palette.primary.withValues(alpha: 0.55)
          ..strokeWidth = 2;
        canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(LaneMetrics.radius * s)), line);
        final y = vp.toScreen(Offset(0, d.y)).dy;
        line
          ..color = palette.primary
          ..strokeWidth = 3;
        canvas.drawLine(
          Offset(r.left + LaneMetrics.padding * s, y),
          Offset(r.right - LaneMetrics.padding * s, y),
          line,
        );
      }
    }

    final sel = session.selection.value;
    final hover = session.hover.value;
    if (hover != null && !sel.contains(hover)) {
      final si = scene.byId(hover);
      if (si != null) {
        line
          ..color = palette.primary.withValues(alpha: 0.45)
          ..strokeWidth = 1.5;
        canvas.drawRRect(RRect.fromRectAndRadius(_screenOf(si).inflate(2), Radius.circular(_radius(si, s))), line);
      }
    }

    if (sel.isNotEmpty) {
      line
        ..color = palette.primary
        ..strokeWidth = 2;
      final view = Offset.zero & size;
      for (final id in sel) {
        if (id == session.lifted.editing) continue;
        final si = scene.byId(id);
        if (si == null) continue;
        final r = _screenOf(si).inflate(3);
        if (!r.overlaps(view)) continue;
        canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(_radius(si, s))), line);
      }
    }

    final m = session.marquee.value;
    if (m != null) {
      final r = vp.rectToScreen(m);
      fill.color = palette.primary.withValues(alpha: 0.08);
      canvas.drawRect(r, fill);
      line
        ..color = palette.primary.withValues(alpha: 0.7)
        ..strokeWidth = 1;
      canvas.drawRect(r, line);
    }

    for (final p in peers.value) {
      final id = p.editing;
      if (id == null || p.view != 'canvas') continue;
      final si = scene.byId(id);
      if (si == null) continue;
      final accent = pastelAt(p.colorIndex).accent;
      final r = _screenOf(si).inflate(4);
      line
        ..color = accent
        ..strokeWidth = 2;
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(_radius(si, s) + 1)), line);
      final label = strings.canvasEditing(p.name);
      final tp = session.text.obtain(
        'e:${p.key}',
        label,
        11,
        palette.text,
        () =>
            boardPainter(label, boardText(11, palette.text, weight: FontWeight.w700), maxLines: 1, strut: false)
              ..layout(maxWidth: 180),
        force: true,
      )!;
      final pill = RRect.fromRectAndRadius(
        Rect.fromLTWH(r.left, r.top - tp.height - 10, tp.width + 14, tp.height + 6),
        const Radius.circular(10),
      );
      fill.color = pastelAt(p.colorIndex).paper(palette.brightness);
      canvas.drawRRect(pill, fill);
      line.strokeWidth = 1.5;
      canvas.drawRRect(pill, line);
      tp.paint(canvas, Offset(pill.left + 7, pill.top + 3));
    }

    final ring = session.eraserRing.value;
    if (ring != null) {
      line
        ..color = palette.muted.withValues(alpha: 0.8)
        ..strokeWidth = 1.5;
      canvas.drawCircle(ring, BoardInputConstants.eraserRadius, line);
    }
  }

  @override
  bool shouldRepaint(OverlayPainter old) =>
      old.session != session || old.palette != palette || old.peers != peers || old.strings != strings;
}

/// Thresholds shared by input and painting.
abstract final class BoardInputConstants {
  /// Eraser radius in screen pixels (14 / scale in canvas units).
  static const eraserRadius = 14.0;
}
