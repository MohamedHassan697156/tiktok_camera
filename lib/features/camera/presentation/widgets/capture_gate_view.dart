import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

/// Full-screen explanation shown when there is no preview to show: access was
/// refused, or the camera failed to open.
///
/// Every variant offers a way forward — retry, or the system settings screen —
/// because a dead end with no button is where users conclude the app is broken.
class CaptureGateView extends StatelessWidget {
  const CaptureGateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          // Keeps the copy readable rather than stretching a sentence across a
          // tablet.
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 56, color: AppColors.onDarkMuted),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.onDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.onDarkMuted,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onPrimary,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.onDark,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
                      ),
                    ),
                    child: Text(primaryLabel),
                  ),
                ),
                if (secondaryLabel != null && onSecondary != null) ...<Widget>[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onSecondary,
                    style: TextButton.styleFrom(foregroundColor: AppColors.onDarkMuted),
                    child: Text(secondaryLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
