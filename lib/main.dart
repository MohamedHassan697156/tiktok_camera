import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
//dfd
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The capture screen is portrait, like the app it is modelled on: a rotating
  // preview would either letterbox the frame or re-crop it mid-take. Layouts are
  // still driven by constraints rather than fixed sizes, so the same screens
  // adapt from a small phone to a tablet.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  // Draw behind the status and navigation bars so the preview is full-bleed, with
  // light icons for the dark UI.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const TikTokCameraApp());
}
