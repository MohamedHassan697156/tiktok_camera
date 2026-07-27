import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/utils/duration_format.dart';

/// The `mm:ss` readout shown while a take runs.
///
/// The dot pulses because a still red dot next to a number that only changes once
/// a second gives no sign the camera is actually running.
class RecordingTimerBadge extends StatefulWidget {
  const RecordingTimerBadge({super.key, required this.elapsed});

  final Duration elapsed;

  @override
  State<RecordingTimerBadge> createState() => _RecordingTimerBadgeState();
}

class _RecordingTimerBadgeState extends State<RecordingTimerBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    duration: const Duration(milliseconds: 900),
    vsync: this,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.controlScrim,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0.25).animate(_pulse),
            child: Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            widget.elapsed.asClock,
            style: const TextStyle(
              color: AppColors.onDark,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              // Tabular figures stop the badge from twitching as digits change
              // width.
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
