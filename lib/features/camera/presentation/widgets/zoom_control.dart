import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../domain/zoom_range.dart';

/// Slim zoom slider shown above the shutter.
///
/// Pinching the preview does the same job and is what most people reach for, but
/// a visible control makes the capability discoverable and gives one-handed users
/// a way to zoom without a second finger.
class ZoomControl extends StatelessWidget {
  const ZoomControl({
    super.key,
    required this.range,
    required this.value,
    required this.onChanged,
  });

  final ZoomRange range;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _ZoomLabel(value: value),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: AppColors.onDark,
              inactiveTrackColor: AppColors.onDark.withValues(alpha: 0.3),
              thumbColor: AppColors.onDark,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              // The slider is a fine adjustment on top of pinch, so it does not
              // need tick marks or a value bubble competing with the preview.
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: range.clamp(value),
              min: range.min,
              max: range.max,
              onChanged: onChanged,
              semanticFormatterCallback: (double zoom) =>
                  '${zoom.toStringAsFixed(1)} times zoom',
            ),
          ),
        ),
      ],
    );
  }
}

class _ZoomLabel extends StatelessWidget {
  const _ZoomLabel({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Fixed width so the slider does not shift as the number grows a digit.
      width: 48,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.controlScrim,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${value.toStringAsFixed(1)}x',
        style: const TextStyle(
          color: AppColors.onDark,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
