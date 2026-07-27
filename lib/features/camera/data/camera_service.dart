import 'dart:async';
import 'dart:ui' show Offset;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

import '../domain/camera_failure.dart';
import '../domain/flash_setting.dart';
import '../domain/zoom_range.dart';

/// Owns the `camera` plugin controller and translates its API into the small set
/// of operations this app needs.
///
/// Keeping the plugin behind this seam means the cubit never touches
/// `CameraException`, never has to remember that switching lenses invalidates the
/// zoom range, and can be unit-tested against a fake. The live [controller] is
/// still exposed because `CameraPreview` needs the real object to find its
/// texture — that is the one detail that cannot be abstracted away without
/// reimplementing the preview widget.
class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = const <CameraDescription>[];

  /// Whether the current controller has already reported a device error, so a
  /// single fault is announced once rather than on every value change.
  bool _reportedDeviceError = false;

  /// Called when the camera hardware itself fails after a successful start —
  /// a HAL crash, or the sensor being taken away.
  ///
  /// This is not the same as an operation failing: the controller is dead and no
  /// further calls on it will work, so the owner has to rebuild it rather than
  /// retry. Without this hook such a fault is silent, and the UI keeps showing a
  /// frozen preview and a shutter that does nothing.
  void Function(String message)? onDeviceError;

  /// How long to wait for the encoder to finalise a clip before giving up.
  ///
  /// `stopVideoRecording` never completes if the capture session died mid-take,
  /// which would otherwise strand the UI in its "saving" state with the shutter
  /// disabled and no way out.
  static const Duration _finaliseTimeout = Duration(seconds: 12);

  /// The controller backing the current preview, or `null` when the camera is
  /// stopped.
  CameraController? get controller => _controller;

  /// Whether a controller exists and has finished initialising.
  bool get isReady => _controller?.value.isInitialized ?? false;

  /// Whether a recording is currently in progress.
  bool get isRecording => _controller?.value.isRecordingVideo ?? false;

  /// Direction the active lens faces.
  CameraLensDirection? get lensDirection => _controller?.description.lensDirection;

  /// Whether the device has a second lens to switch to.
  bool get canSwitchLens =>
      _cameras.map((CameraDescription c) => c.lensDirection).toSet().length > 1;

  /// Starts (or restarts) the camera on the lens facing [direction].
  ///
  /// Any previous controller is disposed first, so this doubles as the recovery
  /// path after the OS reclaims the camera while the app is backgrounded.
  Future<CameraController> start({
    CameraLensDirection direction = CameraLensDirection.back,
    ResolutionPreset resolution = ResolutionPreset.high,
  }) async {
    await _loadCameras();
    final CameraDescription description = _describe(direction);
    await stop();

    final CameraController controller = CameraController(
      description,
      resolution,
      // A muted clip is not what "video recording" promises, so audio is on and
      // the microphone permission is requested up front alongside the camera.
      enableAudio: true,
    );
    _controller = controller;

    try {
      await controller.initialize();
    } on CameraException catch (error) {
      _controller = null;
      await controller.dispose();
      throw CameraFailure(_describeError(error), cause: error);
    }

    _reportedDeviceError = false;
    controller.addListener(_watchForDeviceError);

    // Pin the capture orientation to portrait.
    //
    // Without this, `CameraPreview` picks its rotation and aspect ratio from the
    // *device* orientation, which the plugin keeps reporting from the sensors even
    // though the app itself is locked to portrait. The preview would then rotate
    // its contents inside a box that did not rotate with it. Locking makes both
    // the preview geometry and the recorded orientation deterministic, which is
    // also what lets the preview surface compute its own cover-crop and map taps
    // back to sensor coordinates.
    await _ignoringUnsupported(
      () => controller.lockCaptureOrientation(DeviceOrientation.portraitUp),
    );

    // Continuous autofocus is the sane default; a tap later switches to a locked
    // point. Not every sensor supports every mode, and failing to set a *default*
    // is not worth aborting startup over.
    await _ignoringUnsupported(() => controller.setFocusMode(FocusMode.auto));
    await _ignoringUnsupported(() => controller.setExposureMode(ExposureMode.auto));

    return controller;
  }

  /// Rebuilds the preview on the opposite lens, returning the new controller.
  ///
  /// The plugin can retarget an existing controller, but a fresh one is used
  /// instead: the two sensors have different zoom ranges and flash hardware, and
  /// starting clean guarantees callers re-read those instead of carrying stale
  /// values across the switch.
  Future<CameraController> switchLens() async {
    final CameraLensDirection current = lensDirection ?? CameraLensDirection.back;
    final CameraLensDirection next = current == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    return start(direction: next);
  }

  /// Releases the camera. Safe to call when already stopped.
  Future<void> stop() async {
    final CameraController? controller = _controller;
    _controller = null;
    if (controller == null) return;
    controller.removeListener(_watchForDeviceError);
    try {
      if (controller.value.isRecordingVideo) {
        await controller.stopVideoRecording();
      }
    } catch (_) {
      // Discarding a half-finished clip during teardown is intended.
    }
    await controller.dispose();
  }

  /// Reads the zoom factors the active sensor supports.
  Future<ZoomRange> zoomRange() async {
    final CameraController controller = _require();
    try {
      final double min = await controller.getMinZoomLevel();
      final double max = await controller.getMaxZoomLevel();
      return ZoomRange(min: min, max: max);
    } on CameraException {
      return ZoomRange.none;
    }
  }

  /// Applies a zoom factor, which callers should already have clamped to the
  /// range reported by [zoomRange].
  Future<void> setZoom(double level) async {
    final CameraController controller = _require();
    await _ignoringUnsupported(() => controller.setZoomLevel(level));
  }

  /// Focuses and meters exposure on [point], expressed in preview-relative
  /// coordinates where `(0,0)` is the top-left of the visible frame.
  Future<void> focusOn(Offset point) async {
    final CameraController controller = _require();
    // Locking focus is what makes a tap "stick"; without it continuous AF drifts
    // straight back off the subject.
    await _ignoringUnsupported(() => controller.setFocusPoint(point));
    await _ignoringUnsupported(() => controller.setExposurePoint(point));
    await _ignoringUnsupported(() => controller.setFocusMode(FocusMode.locked));
  }

  /// Returns to continuous autofocus, undoing a previous [focusOn].
  Future<void> resetFocus() async {
    final CameraController controller = _require();
    await _ignoringUnsupported(() => controller.setFocusPoint(null));
    await _ignoringUnsupported(() => controller.setExposurePoint(null));
    await _ignoringUnsupported(() => controller.setFocusMode(FocusMode.auto));
  }

  /// Sets the torch state.
  ///
  /// Returns `false` when the active lens has no usable light — most front
  /// cameras — so the UI can tell the user instead of leaving a dead toggle.
  Future<bool> setFlash(FlashSetting setting) async {
    final CameraController controller = _require();
    try {
      await controller.setFlashMode(setting.mode);
      return true;
    } on CameraException {
      return false;
    }
  }

  /// Begins recording to a temporary file managed by the plugin.
  Future<void> startRecording() async {
    final CameraController controller = _require();
    if (controller.value.isRecordingVideo) return;
    try {
      await controller.startVideoRecording();
    } on CameraException catch (error) {
      throw CameraFailure(_describeError(error), cause: error);
    }
  }

  /// Stops recording and returns the plugin's temporary file.
  ///
  /// The file lives in a cache directory the plugin may clear, so callers must
  /// hand it to the repository to be persisted.
  Future<XFile> stopRecording() async {
    final CameraController controller = _require();
    try {
      return await controller.stopVideoRecording().timeout(_finaliseTimeout);
    } on TimeoutException catch (error) {
      throw CameraFailure(
        'The recording could not be saved — the camera stopped responding.',
        cause: error,
      );
    } on CameraException catch (error) {
      throw CameraFailure(_describeError(error), cause: error);
    }
  }

  /// Watches the controller for hardware faults raised after a successful start.
  void _watchForDeviceError() {
    if (_reportedDeviceError) return;
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.hasError) return;

    _reportedDeviceError = true;
    onDeviceError?.call(
      controller.value.errorDescription ?? 'The camera stopped unexpectedly.',
    );
  }

  Future<void> _loadCameras() async {
    if (_cameras.isNotEmpty) return;
    try {
      _cameras = await availableCameras();
    } on CameraException catch (error) {
      throw CameraFailure('Could not read the list of cameras.', cause: error);
    }
    if (_cameras.isEmpty) {
      throw const CameraFailure('This device has no camera available.');
    }
  }

  /// Picks the lens facing [direction], falling back to whatever exists so a
  /// device with only one camera still starts.
  CameraDescription _describe(CameraLensDirection direction) {
    for (final CameraDescription camera in _cameras) {
      if (camera.lensDirection == direction) return camera;
    }
    return _cameras.first;
  }

  CameraController _require() {
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw const CameraFailure('The camera is not running.');
    }
    return controller;
  }

  /// Runs a capability call, swallowing the "this sensor cannot do that" errors.
  ///
  /// Zoom, focus point and exposure point are all optional hardware features.
  /// A device that lacks one should still give a working camera, so these
  /// failures are downgraded to a debug log rather than surfaced.
  Future<void> _ignoringUnsupported(Future<void> Function() action) async {
    try {
      await action();
    } on CameraException catch (error) {
      debugPrint('CameraService: unsupported operation (${error.code}): ${error.description}');
    }
  }

  /// Turns a plugin error code into something a user can act on.
  String _describeError(CameraException error) {
    switch (error.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'AudioAccessDenied':
      case 'AudioAccessDeniedWithoutPrompt':
        return 'Camera or microphone access was denied.';
      case 'CameraAccessRestricted':
      case 'AudioAccessRestricted':
        return 'Camera access is restricted on this device.';
      case 'cameraNotFound':
        return 'No camera was found on this device.';
      case 'videoRecordingFailed':
        return 'Recording failed. Please try again.';
      default:
        return error.description ?? 'The camera reported an unexpected error.';
    }
  }
}
