import 'package:camera/camera.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/filters/filter_preset.dart';
import '../../../../core/filters/filter_presets.dart';
import '../../domain/flash_setting.dart';
import '../../domain/recording.dart';
import '../../domain/recording_limits.dart';
import '../../domain/zoom_range.dart';

/// Where the camera is in its lifecycle.
enum CameraStatus {
  /// Nothing has been attempted yet.
  initial,

  /// Waiting on the user's answer to the permission prompt.
  requestingPermission,

  /// Refused, but re-asking will show the prompt again.
  permissionDenied,

  /// Refused for good; only system settings can undo it.
  permissionPermanentlyDenied,

  /// Opening the sensor.
  initializing,

  /// Previewing and able to record.
  ready,

  /// Unrecoverable without user action; see [CameraState.errorMessage].
  failure,
}

/// Where the current take is.
enum RecordingStatus {
  /// Not recording.
  idle,

  /// Capturing.
  recording,

  /// Capture finished; the clip is being moved into the library.
  saving,
}

/// Everything the camera screen renders from.
class CameraState extends Equatable {
  CameraState({
    this.status = CameraStatus.initial,
    this.recordingStatus = RecordingStatus.idle,
    this.controller,
    this.lensDirection = CameraLensDirection.back,
    this.canSwitchLens = false,
    this.flash = FlashSetting.off,
    FilterPreset? filter,
    this.zoomRange = ZoomRange.none,
    this.zoom = 1.0,
    this.elapsed = Duration.zero,
    this.errorMessage,
    this.notice,
    this.lastRecording,
  }) : filter = filter ?? FilterPresets.original;

  /// Lifecycle position.
  final CameraStatus status;

  /// Position of the current take.
  final RecordingStatus recordingStatus;

  /// Live controller, needed by `CameraPreview` to locate its texture. `null`
  /// whenever the camera is not running.
  final CameraController? controller;

  /// Which way the active lens faces.
  final CameraLensDirection lensDirection;

  /// Whether the device has another lens, i.e. whether to offer the switch
  /// button at all.
  final bool canSwitchLens;

  /// Torch state.
  final FlashSetting flash;

  /// The look applied to the preview, and recorded against the next clip.
  final FilterPreset filter;

  /// Zoom factors the active sensor supports.
  final ZoomRange zoomRange;

  /// Current zoom factor.
  final double zoom;

  /// How long the current take has been running.
  final Duration elapsed;

  /// Why the camera cannot run, when [status] is [CameraStatus.failure].
  final String? errorMessage;

  /// A one-off message for the user, cleared once shown.
  final String? notice;

  /// The clip just saved, for the UI to navigate to. Cleared once handled.
  final Recording? lastRecording;

  /// Whether the preview is live.
  bool get isReady => status == CameraStatus.ready && controller != null;

  /// Whether a take is in progress.
  bool get isRecording => recordingStatus == RecordingStatus.recording;

  /// Whether the shutter should be disabled because work is in flight.
  bool get isBusy =>
      recordingStatus == RecordingStatus.saving || status == CameraStatus.initializing;

  /// Whether the user still needs to grant access.
  bool get needsPermission =>
      status == CameraStatus.permissionDenied ||
      status == CameraStatus.permissionPermanentlyDenied;

  /// Fraction of the maximum take length used so far, for the progress ring.
  double get recordingProgress {
    final double fraction =
        elapsed.inMilliseconds / RecordingLimits.maxDuration.inMilliseconds;
    return fraction.clamp(0.0, 1.0);
  }

  /// Whether the zoom control is meaningful on this sensor.
  bool get canZoom => zoomRange.isSupported;

  CameraState copyWith({
    CameraStatus? status,
    RecordingStatus? recordingStatus,
    CameraController? controller,
    bool clearController = false,
    CameraLensDirection? lensDirection,
    bool? canSwitchLens,
    FlashSetting? flash,
    FilterPreset? filter,
    ZoomRange? zoomRange,
    double? zoom,
    Duration? elapsed,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? notice,
    bool clearNotice = false,
    Recording? lastRecording,
    bool clearLastRecording = false,
  }) {
    return CameraState(
      status: status ?? this.status,
      recordingStatus: recordingStatus ?? this.recordingStatus,
      controller: clearController ? null : (controller ?? this.controller),
      lensDirection: lensDirection ?? this.lensDirection,
      canSwitchLens: canSwitchLens ?? this.canSwitchLens,
      flash: flash ?? this.flash,
      filter: filter ?? this.filter,
      zoomRange: zoomRange ?? this.zoomRange,
      zoom: zoom ?? this.zoom,
      elapsed: elapsed ?? this.elapsed,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      notice: clearNotice ? null : (notice ?? this.notice),
      lastRecording: clearLastRecording ? null : (lastRecording ?? this.lastRecording),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    recordingStatus,
    controller,
    lensDirection,
    canSwitchLens,
    flash,
    filter,
    zoomRange,
    zoom,
    elapsed,
    errorMessage,
    notice,
    lastRecording,
  ];
}
