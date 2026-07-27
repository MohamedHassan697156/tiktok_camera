import 'dart:async';
import 'dart:io';
import 'dart:ui' show Offset;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/filters/filter_preset.dart';
import '../../../../core/filters/filter_presets.dart';
import '../../data/camera_service.dart';
import '../../data/capture_permission_service.dart';
import '../../data/recording_repository.dart';
import '../../domain/camera_failure.dart';
import '../../domain/flash_setting.dart';
import '../../domain/recording_limits.dart';
import '../../domain/storage_failure.dart';
import 'camera_state.dart';

/// Drives the capture screen: permissions, sensor lifecycle, camera controls and
/// the recording clock.
///
/// The cubit is the only thing that decides *when* the camera runs. Widgets
/// report intent (a tap, a pinch, the app going to the background) and read the
/// resulting state; they never call the plugin.
class CameraCubit extends Cubit<CameraState> {
  CameraCubit({
    CameraService? cameraService,
    CapturePermissionService permissionService = const CapturePermissionService(),
    RecordingRepository repository = const RecordingRepository(),
  }) : _camera = cameraService ?? CameraService(),
       _permissions = permissionService,
       _repository = repository,
       super(CameraState()) {
    _camera.onDeviceError = _handleDeviceError;
  }

  final CameraService _camera;
  final CapturePermissionService _permissions;
  final RecordingRepository _repository;

  /// Refreshes [CameraState.elapsed] while a take runs.
  Timer? _ticker;

  /// Wall-clock start of the current take. Elapsed time is measured against this
  /// rather than counted in ticks, so a dropped frame or a busy isolate cannot
  /// make the timer drift behind the actual recording.
  DateTime? _startedAt;

  /// Guards the lens switch, which tears down and rebuilds the controller and
  /// must not overlap with itself.
  bool _isSwitchingLens = false;

  /// Asks for permission if needed, then opens the camera.
  ///
  /// Safe to call again after a refusal — that is exactly what the "try again"
  /// button does.
  Future<void> start() async {
    emit(state.copyWith(status: CameraStatus.requestingPermission, clearErrorMessage: true));

    final CapturePermissionStatus permission = await _permissions.request();
    if (isClosed) return;

    switch (permission) {
      case CapturePermissionStatus.granted:
        await _openCamera();
      case CapturePermissionStatus.denied:
        emit(state.copyWith(status: CameraStatus.permissionDenied, clearController: true));
      case CapturePermissionStatus.permanentlyDenied:
        emit(
          state.copyWith(
            status: CameraStatus.permissionPermanentlyDenied,
            clearController: true,
          ),
        );
    }
  }

  /// Sends the user to system settings, the only route back from a permanent
  /// refusal.
  Future<void> openSystemSettings() => _permissions.openSettings();

  /// Rebuilds the preview on the other lens.
  Future<void> switchLens() async {
    if (!state.isReady || _isSwitchingLens) return;
    // Switching mid-take would split the clip in two; the button is disabled in
    // the UI, and this is the guard behind it.
    if (state.isRecording) return;

    _isSwitchingLens = true;
    // The old controller is disposed as part of starting the new one, so it has
    // to leave the state first — a `CameraPreview` holding a disposed controller
    // throws on its next build.
    emit(
      state.copyWith(
        status: CameraStatus.initializing,
        clearController: true,
        // Front lenses rarely have a torch; starting the new lens dark avoids
        // showing an "on" toggle that controls nothing.
        flash: FlashSetting.off,
      ),
    );

    try {
      final CameraController controller = await _camera.switchLens();
      if (isClosed) return;
      await _afterCameraStarted(controller);
    } on CameraFailure catch (failure) {
      _emitFailure(failure);
    } finally {
      _isSwitchingLens = false;
    }
  }

  /// Turns the torch on or off.
  Future<void> toggleFlash() async {
    if (!state.isReady) return;
    final FlashSetting next = state.flash.toggled;
    final bool applied = await _camera.setFlash(next);
    if (isClosed) return;

    if (!applied) {
      emit(state.copyWith(notice: 'This camera has no flash.'));
      return;
    }
    emit(state.copyWith(flash: next));
  }

  /// Selects the look applied to the preview and stamped on the next clip.
  void selectFilter(FilterPreset filter) {
    if (state.filter == filter) return;
    emit(state.copyWith(filter: filter));
  }

  /// Applies a zoom factor, clamped to what the sensor supports.
  Future<void> setZoom(double level) async {
    if (!state.isReady || !state.canZoom) return;
    final double clamped = state.zoomRange.clamp(level);
    if ((clamped - state.zoom).abs() < 0.01) return;

    emit(state.copyWith(zoom: clamped));
    await _camera.setZoom(clamped);
  }

  /// Focuses and meters on [point], in preview-relative coordinates where
  /// `(0,0)` is the top-left of the visible frame.
  Future<void> focusAt(Offset point) async {
    if (!state.isReady) return;
    await _camera.focusOn(point);
  }

  /// Starts a take, or ends the one in progress.
  Future<void> toggleRecording() async {
    if (!state.isReady || state.isBusy) return;
    if (state.isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  /// Releases the camera while the capture screen is not the one in front.
  ///
  /// Called both when the app leaves the foreground and when another screen is
  /// pushed over the preview. Android hands the sensor to whichever app is in
  /// front, so holding it while backgrounded either fails or blocks other apps;
  /// and holding it behind the playback screen burns power while contending with
  /// the video decoder. A take in progress is saved rather than dropped — the
  /// user's footage is not ours to discard.
  Future<void> releaseCamera() async {
    // Android pauses the activity behind the permission sheet. Tearing down here
    // would abandon the request that is still in flight and leave the screen
    // stuck on a spinner, so the opening handshake is left alone.
    if (state.status == CameraStatus.requestingPermission) return;

    if (state.isRecording) {
      await _stopRecording(interrupted: true);
    }
    _ticker?.cancel();
    _ticker = null;
    await _camera.stop();
    if (isClosed) return;

    emit(
      state.copyWith(
        clearController: true,
        // Keep a permission verdict on screen; otherwise show the opening state
        // so the resume path has something to replace.
        status: state.needsPermission ? state.status : CameraStatus.initializing,
      ),
    );
  }

  /// Reopens the camera when the capture screen is in front again.
  Future<void> restoreCamera() async {
    if (state.controller != null) return;

    // The user may have granted access in system settings while we were away, so
    // re-check rather than trusting the last verdict.
    final CapturePermissionStatus permission = await _permissions.check();
    if (isClosed) return;

    switch (permission) {
      case CapturePermissionStatus.granted:
        await _openCamera();
      case CapturePermissionStatus.denied:
        emit(state.copyWith(status: CameraStatus.permissionDenied));
      case CapturePermissionStatus.permanentlyDenied:
        emit(state.copyWith(status: CameraStatus.permissionPermanentlyDenied));
    }
  }

  /// Acknowledges the current [CameraState.notice] so it is not shown twice.
  void clearNotice() {
    if (state.notice == null) return;
    emit(state.copyWith(clearNotice: true));
  }

  /// Acknowledges [CameraState.lastRecording] once the UI has navigated to it.
  void clearLastRecording() {
    if (state.lastRecording == null) return;
    emit(state.copyWith(clearLastRecording: true));
  }

  @override
  Future<void> close() async {
    _ticker?.cancel();
    _ticker = null;
    await _camera.stop();
    return super.close();
  }

  Future<void> _openCamera() async {
    emit(state.copyWith(status: CameraStatus.initializing, clearErrorMessage: true));
    try {
      final CameraController controller = await _camera.start(direction: state.lensDirection);
      if (isClosed) return;
      await _afterCameraStarted(controller);
    } on CameraFailure catch (failure) {
      _emitFailure(failure);
    }
  }

  /// Re-reads the capabilities that belong to the sensor that just opened.
  Future<void> _afterCameraStarted(CameraController controller) async {
    final zoom = await _camera.zoomRange();
    if (isClosed) return;

    // Carry the torch across a restart, but drop it silently if this sensor has
    // no light — an explicit toggle is where the user gets told.
    FlashSetting flash = state.flash;
    if (flash.isOn && !await _camera.setFlash(flash)) {
      flash = FlashSetting.off;
    }
    if (isClosed) return;

    emit(
      state.copyWith(
        status: CameraStatus.ready,
        controller: controller,
        lensDirection: controller.description.lensDirection,
        canSwitchLens: _camera.canSwitchLens,
        zoomRange: zoom,
        zoom: zoom.min,
        flash: flash,
        elapsed: Duration.zero,
        recordingStatus: RecordingStatus.idle,
        clearErrorMessage: true,
      ),
    );
  }

  Future<void> _startRecording() async {
    try {
      await _camera.startRecording();
    } on CameraFailure catch (failure) {
      if (!isClosed) emit(state.copyWith(notice: failure.message));
      return;
    }
    if (isClosed) return;

    _startedAt = DateTime.now();
    emit(state.copyWith(recordingStatus: RecordingStatus.recording, elapsed: Duration.zero));
    _ticker = Timer.periodic(RecordingLimits.tick, _onTick);
  }

  void _onTick(Timer timer) {
    final DateTime? startedAt = _startedAt;
    if (startedAt == null || isClosed) return;

    final Duration elapsed = DateTime.now().difference(startedAt);
    if (elapsed >= RecordingLimits.maxDuration) {
      // _stopRecording cancels this ticker, so it cannot fire again mid-stop.
      unawaited(_stopRecording(reachedLimit: true));
      return;
    }
    emit(state.copyWith(elapsed: elapsed));
  }

  /// Ends the take and files the clip.
  ///
  /// [reachedLimit] means the one-minute ceiling stopped it; [interrupted] means
  /// the app was backgrounded. Both are worth telling the user, because in
  /// neither case did they press stop.
  Future<void> _stopRecording({bool reachedLimit = false, bool interrupted = false}) async {
    _ticker?.cancel();
    _ticker = null;

    final DateTime? startedAt = _startedAt;
    _startedAt = null;

    if (!_camera.isRecording) {
      if (!isClosed) {
        emit(state.copyWith(recordingStatus: RecordingStatus.idle, elapsed: Duration.zero));
      }
      return;
    }

    emit(state.copyWith(recordingStatus: RecordingStatus.saving));

    try {
      final XFile capture = await _camera.stopRecording();
      final Duration duration = startedAt == null
          ? state.elapsed
          : DateTime.now().difference(startedAt);

      if (duration < RecordingLimits.minDuration) {
        await _discard(capture);
        if (isClosed) return;
        emit(
          state.copyWith(
            recordingStatus: RecordingStatus.idle,
            elapsed: Duration.zero,
            notice: 'That was too short — try holding on a moment longer.',
          ),
        );
        return;
      }

      final recording = await _repository.persist(
        sourcePath: capture.path,
        duration: duration,
        filterId: state.filter.id,
      );
      if (isClosed) return;

      emit(
        state.copyWith(
          recordingStatus: RecordingStatus.idle,
          elapsed: Duration.zero,
          lastRecording: recording,
          notice: reachedLimit
              ? 'Reached the one-minute limit.'
              : interrupted
              ? 'Recording stopped and saved when the app was interrupted.'
              : null,
        ),
      );
    } on CameraFailure catch (failure) {
      _emitRecordingError(failure.message);
      // A stop that failed or timed out leaves the capture session in an unknown
      // state — the encoder may be half torn down. A fresh controller is the only
      // reliable way back to a working preview, and without it the user is left
      // looking at a frozen frame.
      await _restartCamera();
    } on StorageFailure catch (failure) {
      // Storage failed but the camera is fine; there is nothing to rebuild.
      _emitRecordingError(failure.message);
    }
  }

  /// Handles a hardware fault reported after the camera was already running.
  ///
  /// The controller is dead at this point, so it is dropped rather than retried:
  /// the screen shows the reason with a "try again" button instead of a preview
  /// frozen on its last frame.
  void _handleDeviceError(String message) {
    _ticker?.cancel();
    _ticker = null;
    _startedAt = null;
    if (isClosed) return;

    unawaited(
      _camera.stop().catchError((Object error) {
        debugPrint('CameraCubit: teardown after device error failed: $error');
      }),
    );

    emit(
      state.copyWith(
        status: CameraStatus.failure,
        errorMessage: message,
        recordingStatus: RecordingStatus.idle,
        elapsed: Duration.zero,
        clearController: true,
      ),
    );
  }

  /// Tears the camera down and opens it again from scratch.
  Future<void> _restartCamera() async {
    if (isClosed) return;
    try {
      await _camera.stop();
    } catch (error) {
      debugPrint('CameraCubit: could not release the camera cleanly: $error');
    }
    if (isClosed) return;
    await _openCamera();
  }

  /// Removes a capture we decided not to keep.
  Future<void> _discard(XFile capture) async {
    try {
      final File file = File(capture.path);
      if (file.existsSync()) await file.delete();
    } catch (error) {
      debugPrint('CameraCubit: could not discard capture: $error');
    }
  }

  void _emitFailure(CameraFailure failure) {
    if (isClosed) return;
    emit(
      state.copyWith(
        status: CameraStatus.failure,
        errorMessage: failure.message,
        clearController: true,
      ),
    );
  }

  void _emitRecordingError(String message) {
    if (isClosed) return;
    emit(
      state.copyWith(
        recordingStatus: RecordingStatus.idle,
        elapsed: Duration.zero,
        notice: message,
      ),
    );
  }

  /// Exposed for tests, which need to assert the default look is the neutral one.
  @visibleForTesting
  static FilterPreset get defaultFilter => FilterPresets.original;
}
