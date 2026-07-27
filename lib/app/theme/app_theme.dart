import 'package:flutter/material.dart';

/// The app's palette.
///
/// A capture UI sits on top of live video, so the surfaces here are deliberately
/// either pure black or translucent: anything opaque and mid-toned would fight
/// the image behind it.
abstract final class AppColors {
  /// Behind the preview, and the letterbox around it.
  static const Color background = Color(0xFF000000);

  /// Panels that sit above the preview, such as the filter tray.
  static const Color surface = Color(0xFF141416);

  /// Primary accent: the record button and destructive confirmations.
  static const Color accent = Color(0xFFFE2C55);

  /// Secondary accent, used for the recording progress ring.
  static const Color accentAlt = Color(0xFF25F4EE);

  /// Foreground on dark surfaces.
  static const Color onDark = Color(0xFFFFFFFF);

  /// Secondary foreground, for labels that must not compete with controls.
  static const Color onDarkMuted = Color(0xB3FFFFFF);

  /// Scrim behind control clusters, so white icons stay legible over a bright
  /// preview without hiding the image.
  static const Color controlScrim = Color(0x59000000);
}

/// Visual configuration shared by the capture, playback and library screens.
abstract final class AppTheme {
  /// The only theme: a camera UI has no light mode to speak of, because the
  /// backdrop is whatever the sensor sees.
  static ThemeData get dark {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
    ).copyWith(
      surface: AppColors.surface,
      primary: AppColors.accent,
      secondary: AppColors.accentAlt,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
      iconTheme: const IconThemeData(color: AppColors.onDark),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.onDark,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface,
        contentTextStyle: const TextStyle(color: AppColors.onDark, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  /// Corner radius shared by tiles and sheets.
  static const double cornerRadius = 16;

  /// Duration used for control-level transitions, kept short so the UI never
  /// feels like it is lagging behind the shutter.
  static const Duration quickTransition = Duration(milliseconds: 220);
}
