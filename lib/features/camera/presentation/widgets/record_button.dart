import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

/// The shutter.
///
/// Idle it is a filled circle; recording it becomes a rounded square, with the
/// ring around it filling to show how much of the one-minute limit is used. The
/// shape carries the state as well as the ring does, which matters on a screen
/// where the user is looking at themselves rather than at the button.
class RecordButton extends StatelessWidget {
  const RecordButton({
    super.key,
    required this.isRecording,
    required this.isBusy,
    required this.progress,
    required this.onPressed,
  });

  final bool isRecording;

  /// Whether a clip is being saved, during which the shutter must not re-trigger.
  final bool isBusy;

  /// Fraction of the maximum take length used, `0..1`.
  final double progress;

  final VoidCallback? onPressed;

  static const double _diameter = 84;
  static const double _strokeWidth = 5;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !isBusy;

    return Semantics(
      button: true,
      enabled: enabled,
      label: isRecording ? 'Stop recording' : 'Start recording',
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: _diameter,
          height: _diameter,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // Track plus progress arc.
              CustomPaint(
                size: const Size.square(_diameter),
                painter: _ProgressRingPainter(
                  progress: isRecording ? progress : 0,
                  strokeWidth: _strokeWidth,
                ),
              ),
              if (isBusy)
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.onDark,
                  ),
                )
              else
                AnimatedContainer(
                  duration: AppTheme.quickTransition,
                  curve: Curves.easeOutCubic,
                  width: isRecording ? 30 : 64,
                  height: isRecording ? 30 : 64,
                  decoration: BoxDecoration(
                    color: enabled ? AppColors.accent : AppColors.accent.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(isRecording ? 8 : 32),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({required this.progress, required this.strokeWidth});

  final double progress;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = size.center(Offset.zero);
    final double radius = (size.shortestSide - strokeWidth) / 2;

    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = AppColors.onDark.withValues(alpha: 0.35);
    canvas.drawCircle(centre, radius, track);

    if (progress <= 0) return;

    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = AppColors.accentAlt;

    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      // Start at twelve o'clock rather than at three, which is where Flutter's
      // zero angle sits.
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_ProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.strokeWidth != strokeWidth;
}
