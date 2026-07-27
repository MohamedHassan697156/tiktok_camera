import 'package:flutter/material.dart';

import '../features/camera/presentation/pages/camera_page.dart';
import 'theme/app_theme.dart';

/// Application root.
///
/// Navigation is plain imperative `Navigator` work rather than a route table:
/// there are only three screens and two of them take a typed argument (a
/// recording), which named routes would force through an untyped map.
class TikTokCameraApp extends StatelessWidget {
  const TikTokCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TikTok Camera',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const CameraPage(),
    );
  }
}
