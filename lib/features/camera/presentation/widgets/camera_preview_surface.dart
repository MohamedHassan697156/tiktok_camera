import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/filters/filter_preset.dart';
import '../../../../core/filters/filtered_view.dart';
import '../../domain/zoom_range.dart';

/// The live preview: full-bleed, graded, and the target for tap-to-focus and
/// pinch-to-zoom.
///
/// The sensor's aspect ratio almost never matches the screen's, so the preview is
/// centre-cropped to fill rather than letterboxed — that is what makes the screen
/// read as a camera and not as a video player. Because the crop hides part of the
/// frame, this widget also owns the arithmetic that turns a tap into the
/// sensor-relative point the focus API expects; nothing else in the app knows how
/// the preview is fitted.
class CameraPreviewSurface extends StatefulWidget {
  const CameraPreviewSurface({
    super.key,
    required this.controller,
    required this.filter,
    required this.zoom,
    required this.zoomRange,
    required this.onFocusRequested,
    required this.onZoomChanged,
  });

  final CameraController controller;
  final FilterPreset filter;
  final double zoom;
  final ZoomRange zoomRange;

  /// Called with a point in `0..1` preview coordinates, origin top-left.
  final ValueChanged<Offset> onFocusRequested;

  /// Called with an absolute zoom factor as the user pinches.
  final ValueChanged<double> onZoomChanged;

  @override
  State<CameraPreviewSurface> createState() => _CameraPreviewSurfaceState();
}

class _CameraPreviewSurfaceState extends State<CameraPreviewSurface> {
  /// Where the last tap landed, in this widget's coordinates, so the reticle can
  /// be drawn there. `null` hides it.
  Offset? _reticleAt;

  /// Bumped on every tap so a second tap in the same place restarts the reticle
  /// animation instead of leaving a stale one on screen.
  int _reticleSequence = 0;

  /// Zoom factor when the current pinch began, so scale is applied relative to it
  /// rather than compounding every frame.
  double _zoomAtPinchStart = 1;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size viewport = constraints.biggest;
        final Size preview = _previewSize;

        return GestureDetector(
          // The preview is a plain texture with nothing hit-testable in it, so it
          // has to opt into receiving gestures over its whole area.
          behavior: HitTestBehavior.opaque,
          onTapUp: (TapUpDetails details) => _handleTap(details.localPosition, viewport, preview),
          onScaleStart: (_) => _zoomAtPinchStart = widget.zoom,
          onScaleUpdate: (ScaleUpdateDetails details) {
            if (!widget.zoomRange.isSupported) return;
            widget.onZoomChanged(_zoomAtPinchStart * details.scale);
          },
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _buildFittedPreview(preview),
                if (_reticleAt != null)
                  _FocusReticle(
                    key: ValueKey<int>(_reticleSequence),
                    position: _reticleAt!,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The preview scaled to cover the viewport, with the overflow clipped.
  Widget _buildFittedPreview(Size preview) {
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: preview.width,
        height: preview.height,
        // Grading sits inside the fitted box, so the filter runs at preview
        // resolution rather than at the (larger) scaled-up size.
        child: AnimatedFilteredView(
          preset: widget.filter,
          child: CameraPreview(widget.controller),
        ),
      ),
    );
  }

  /// The preview's on-screen dimensions.
  ///
  /// `previewSize` is reported in the sensor's own landscape orientation. The
  /// capture orientation is locked to portrait when the camera starts, so the
  /// preview is always presented with the axes swapped.
  Size get _previewSize {
    final Size? reported = widget.controller.value.previewSize;
    if (reported == null || reported.isEmpty) {
      // A square keeps the layout sane for the frame or two before the sensor
      // reports its real size.
      return const Size.square(1080);
    }
    return Size(reported.height, reported.width);
  }

  void _handleTap(Offset local, Size viewport, Size preview) {
    setState(() {
      _reticleAt = local;
      _reticleSequence++;
    });
    widget.onFocusRequested(_toPreviewCoordinates(local, viewport, preview));
  }

  /// Maps a tap in widget coordinates to the `0..1` preview coordinates the focus
  /// API expects, undoing the cover-crop.
  ///
  /// `BoxFit.cover` scales the preview by the larger of the two axis ratios and
  /// centres it, so part of the frame sits outside the viewport. Adding back the
  /// hidden margin is what keeps the focus point under the user's finger instead
  /// of drifting towards the centre.
  Offset _toPreviewCoordinates(Offset local, Size viewport, Size preview) {
    final double scale = math.max(
      viewport.width / preview.width,
      viewport.height / preview.height,
    );
    final Size rendered = Size(preview.width * scale, preview.height * scale);
    final double hiddenLeft = (rendered.width - viewport.width) / 2;
    final double hiddenTop = (rendered.height - viewport.height) / 2;

    return Offset(
      ((local.dx + hiddenLeft) / rendered.width).clamp(0.0, 1.0),
      ((local.dy + hiddenTop) / rendered.height).clamp(0.0, 1.0),
    );
  }
}

/// The square that confirms where focus was requested, then fades out.
///
/// Purely feedback: it is local widget state because nothing outside this screen
/// needs to know a tap happened.
class _FocusReticle extends StatefulWidget {
  const _FocusReticle({super.key, required this.position});

  final Offset position;

  @override
  State<_FocusReticle> createState() => _FocusReticleState();
}

class _FocusReticleState extends State<_FocusReticle> with SingleTickerProviderStateMixin {
  static const double _size = 76;

  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 1400),
    vsync: this,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.position.dx - _size / 2,
      top: widget.position.dy - _size / 2,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            final double t = _controller.value;
            // Snap in over the first fifth, hold, then fade away.
            final double scale = 1.25 - 0.25 * Curves.easeOutBack.transform(math.min(t * 5, 1));
            final double opacity = t < 0.7 ? 1 : 1 - (t - 0.7) / 0.3;
            return Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.scale(scale: scale, child: child),
            );
          },
          child: Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.accentAlt, width: 1.5),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
    );
  }
}
