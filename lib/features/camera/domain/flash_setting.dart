import 'package:camera/camera.dart';

/// The flash states the capture button's neighbour toggles between.
///
/// Only the torch is offered, and that is deliberate. [FlashMode.always] and
/// [FlashMode.auto] drive the pre-capture flash for *photos*; during video
/// recording they fire nothing, so surfacing them would give the user two
/// controls that visibly do nothing. A continuous torch is what actually lights
/// a video, which is also what the TikTok capture screen exposes.
enum FlashSetting {
  off(FlashMode.off, 'Flash off'),
  on(FlashMode.torch, 'Flash on');

  const FlashSetting(this.mode, this.label);

  /// The plugin-level mode this setting maps to.
  final FlashMode mode;

  /// Accessibility label for the toggle.
  final String label;

  /// Whether the torch is lit.
  bool get isOn => this == FlashSetting.on;

  /// The state reached by tapping the toggle.
  FlashSetting get toggled => isOn ? FlashSetting.off : FlashSetting.on;
}
