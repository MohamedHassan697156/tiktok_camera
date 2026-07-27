import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'color_matrix.dart';
import 'filter_preset.dart';

/// Applies a [FilterPreset] to [child].
///
/// This is the only place a preset is turned into render layers. The live camera
/// preview, playback of a finished recording, and the tray swatches all go
/// through it, which is what guarantees a clip looks the same while shooting and
/// while watching it back.
///
/// Both layers are handled by the compositor rather than by Dart code, so the
/// per-frame cost does not depend on the preview resolution and no frame data
/// ever crosses into the Dart isolate.
class FilteredView extends StatelessWidget {
  const FilteredView({super.key, required this.preset, required this.child});

  final FilterPreset preset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (preset.isPassthrough) return child;
    return _FilterLayers(
      matrix: preset.matrix,
      blurSigma: preset.blurSigma,
      child: child,
    );
  }
}

/// [FilteredView] that cross-fades whenever [preset] changes, so switching looks
/// glides instead of snapping.
class AnimatedFilteredView extends ImplicitlyAnimatedWidget {
  const AnimatedFilteredView({
    super.key,
    required this.preset,
    required this.child,
    super.curve = Curves.easeOutCubic,
  }) : super(duration: _crossFade);

  /// Long enough to read as a transition, short enough that the preview never
  /// feels like it is lagging behind the tap. Fixed rather than configurable:
  /// it is a property of how this app switches looks, not of a call site.
  static const Duration _crossFade = Duration(milliseconds: 280);

  final FilterPreset preset;
  final Widget child;

  @override
  AnimatedWidgetBaseState<AnimatedFilteredView> createState() => _AnimatedFilteredViewState();
}

class _AnimatedFilteredViewState extends AnimatedWidgetBaseState<AnimatedFilteredView> {
  ColorMatrixTween? _matrix;
  Tween<double>? _blurSigma;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _matrix =
        visitor(
              _matrix,
              widget.preset.matrix,
              (dynamic value) => ColorMatrixTween(begin: value as ColorMatrix),
            )
            as ColorMatrixTween?;
    _blurSigma =
        visitor(
              _blurSigma,
              widget.preset.blurSigma,
              (dynamic value) => Tween<double>(begin: value as double),
            )
            as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    return _FilterLayers(
      matrix: _matrix?.evaluate(animation) ?? widget.preset.matrix,
      blurSigma: _blurSigma?.evaluate(animation) ?? widget.preset.blurSigma,
      child: widget.child,
    );
  }
}

/// Interpolates a [ColorMatrix] coefficient-wise.
class ColorMatrixTween extends Tween<ColorMatrix> {
  ColorMatrixTween({super.begin, super.end});

  @override
  ColorMatrix lerp(double t) => ColorMatrix.lerp(
    begin ?? ColorMatrix.identity,
    end ?? ColorMatrix.identity,
    t,
  );
}

/// The blur-then-grade layer stack shared by both public widgets.
class _FilterLayers extends StatelessWidget {
  const _FilterLayers({
    required this.matrix,
    required this.blurSigma,
    required this.child,
  });

  final ColorMatrix matrix;
  final double blurSigma;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget result = child;

    // Soften first, grade second: blurring an already-graded image would drag
    // the grade's contrast back down.
    if (blurSigma > 0.01) {
      result = ImageFiltered(
        // Clamped so the blur samples the edge pixels instead of transparency,
        // which would otherwise darken the frame border.
        imageFilter: ui.ImageFilter.blur(
          sigmaX: blurSigma,
          sigmaY: blurSigma,
          tileMode: TileMode.clamp,
        ),
        child: result,
      );
    }

    if (!matrix.isIdentity) {
      result = ColorFiltered(colorFilter: matrix.toColorFilter(), child: result);
    }

    return result;
  }
}
