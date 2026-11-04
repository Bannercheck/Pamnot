import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Content for a [RetainedPicture]: recorded once per [key], shown through
/// [transform].
abstract class RetainedPictureSource {
  /// Notifies when [key] or [transform] may have changed.
  Listenable get repaint;

  /// Identity of the content; a different key records again.
  Object? get key;

  /// Where the recording goes on screen (canvas → local), or null to show
  /// nothing.
  Matrix4? get transform;

  /// Slow recordings (over 4 ms) are redone at most 5 times a second; the
  /// stale picture is shown meanwhile.
  bool get throttle;

  /// Drop the picture while hidden (true for short-lived content).
  bool get releaseWhenHidden;

  void record(Canvas canvas);
}

/// Shows one recorded picture through a transform, as its own layer.
///
/// Drawing a cached picture from a CustomPainter re-records it into every
/// frame (the engine copies its operations), which at overview zoom is
/// proportional to the whole board. Here the PictureLayer is kept across
/// frames and only the TransformLayer above it changes, so a pan or zoom
/// frame costs the same for 50 items or 5,000.
class RetainedPicture extends LeafRenderObjectWidget {
  const RetainedPicture({super.key, required this.source});

  final RetainedPictureSource source;

  @override
  RenderRetainedPicture createRenderObject(BuildContext context) => RenderRetainedPicture(source);

  @override
  void updateRenderObject(BuildContext context, RenderRetainedPicture renderObject) => renderObject.source = source;
}

class RenderRetainedPicture extends RenderBox {
  RenderRetainedPicture(this._source);

  RetainedPictureSource _source;
  RetainedPictureSource get source => _source;
  set source(RetainedPictureSource s) {
    if (identical(s, _source)) return;
    if (attached) _source.repaint.removeListener(markNeedsPaint);
    _source = s;
    if (attached) s.repaint.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  final LayerHandle<PictureLayer> _picture = LayerHandle();
  final LayerHandle<TransformLayer> _transform = LayerHandle();
  Object? _key;
  int _buildMicros = 0;
  final Stopwatch _sinceBuild = Stopwatch();
  Timer? _retry;
  bool _retryDue = false;

  static const slowRecording = Duration(milliseconds: 4);
  static const rerecordEvery = Duration(milliseconds: 200);

  /// How many times the content was recorded (tests check that panning
  /// records nothing).
  @visibleForTesting
  int debugRecordCount = 0;

  /// Microseconds the last recording took.
  int get lastRecordMicros => _buildMicros;

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _source.repaint.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _source.repaint.removeListener(markNeedsPaint);
    _retry?.cancel();
    _retry = null;
    super.detach();
  }

  @override
  void dispose() {
    _retry?.cancel();
    _picture.layer = null;
    _transform.layer = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final m = _source.transform;
    if (m == null) {
      if (_source.releaseWhenHidden && _picture.layer != null) {
        _picture.layer = null;
        _key = null;
      }
      return;
    }
    final key = _source.key;
    var layer = _picture.layer;
    if (layer == null || key != _key) {
      final stale =
          layer != null &&
          !_retryDue &&
          _source.throttle &&
          _buildMicros > slowRecording.inMicroseconds &&
          _sinceBuild.elapsed < rerecordEvery;
      if (stale) {
        // A big board: keep the stale picture a moment, record a bit later.
        _retry ??= Timer(rerecordEvery - _sinceBuild.elapsed, () {
          _retry = null;
          _retryDue = true;
          if (attached) markNeedsPaint();
        });
      } else {
        _retryDue = false;
        final sw = Stopwatch()..start();
        final rec = ui.PictureRecorder();
        _source.record(Canvas(rec));
        final pic = rec.endRecording();
        _buildMicros = sw.elapsedMicroseconds;
        _sinceBuild
          ..reset()
          ..start();
        debugRecordCount++;
        layer ??= PictureLayer(const Rect.fromLTRB(-1e7, -1e7, 1e7, 1e7))..isComplexHint = true;
        // The layer owns the picture and disposes the previous one.
        layer.picture = pic;
        _picture.layer = layer;
        _key = key;
      }
    }
    final retained = _picture.layer!;
    _transform.layer = context.pushTransform(
      needsCompositing,
      offset,
      m,
      (context, _) => context.addLayer(retained),
      oldLayer: _transform.layer,
    );
  }
}
