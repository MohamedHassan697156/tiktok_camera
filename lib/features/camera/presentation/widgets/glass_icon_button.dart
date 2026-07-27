import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

/// A round, translucent icon button for controls that sit directly on the
/// preview.
///
/// The scrim exists so a white glyph stays readable over a bright frame without
/// covering it. Disabled buttons dim rather than disappear, so the control layout
/// does not jump around while the camera is busy.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.label,
    this.isActive = false,
    this.diameter = 44,
  });

  final IconData icon;

  /// `null` disables the button.
  final VoidCallback? onPressed;

  /// Spoken description; the glyph alone means nothing to a screen reader.
  final String semanticLabel;

  /// Optional caption under the button, as on the capture screen's side rail.
  final String? label;

  /// Highlights the button to show the feature it controls is switched on.
  final bool isActive;

  final double diameter;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final Color foreground = isActive ? AppColors.accentAlt : AppColors.onDark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Semantics(
            button: true,
            enabled: enabled,
            label: semanticLabel,
            child: Material(
              color: AppColors.controlScrim,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPressed,
                child: SizedBox(
                  width: diameter,
                  height: diameter,
                  child: Center(
                    child: Icon(icon, size: diameter * 0.5, color: foreground),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (label != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            label!,
            style: TextStyle(
              color: enabled ? AppColors.onDarkMuted : AppColors.onDarkMuted.withValues(alpha: 0.4),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              shadows: const <Shadow>[Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
        ],
      ],
    );
  }
}
