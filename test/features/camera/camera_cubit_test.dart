import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiktokcamera/core/filters/filter_presets.dart';
import 'package:tiktokcamera/features/camera/data/camera_service.dart';
import 'package:tiktokcamera/features/camera/data/capture_permission_service.dart';
import 'package:tiktokcamera/features/camera/domain/camera_failure.dart';
import 'package:tiktokcamera/features/camera/domain/flash_setting.dart';
import 'package:tiktokcamera/features/camera/domain/recording_limits.dart';
import 'package:tiktokcamera/features/camera/presentation/cubit/camera_cubit.dart';
import 'package:tiktokcamera/features/camera/presentation/cubit/camera_state.dart';

/// Answers the permission handshake without touching the platform.
class _StubPermissions extends CapturePermissionService {
  const _StubPermissions(this.result);

  final CapturePermissionStatus result;

  @override
  Future<CapturePermissionStatus> request() async => result;

  @override
  Future<CapturePermissionStatus> check() async => result;
}

/// Stands in for a device whose camera refuses to open.
///
/// Opening a real sensor is out of reach in a unit test, so the paths that need a
/// live `CameraController` are covered on device instead. What is worth asserting
/// here is that a refusal surfaces as a message rather than an unhandled
/// exception.
class _UnavailableCameraService extends CameraService {
  @override
  Future<CameraController> start({
    CameraLensDirection direction = CameraLensDirection.back,
    ResolutionPreset resolution = ResolutionPreset.high,
  }) async {
    throw const CameraFailure('This device has no camera available.');
  }
}

void main() {
  late _UnavailableCameraService cameraService;

  CameraCubit build({
    CapturePermissionStatus permission = CapturePermissionStatus.granted,
  }) {
    cameraService = _UnavailableCameraService();
    return CameraCubit(
      cameraService: cameraService,
      permissionService: _StubPermissions(permission),
    );
  }

  group('initial state', () {
    test('starts idle, neutral and dark', () {
      final CameraCubit cubit = build();
      addTearDown(cubit.close);

      expect(cubit.state.status, CameraStatus.initial);
      expect(cubit.state.recordingStatus, RecordingStatus.idle);
      expect(cubit.state.filter, FilterPresets.original);
      expect(cubit.state.flash, FlashSetting.off);
      expect(cubit.state.elapsed, Duration.zero);
      expect(cubit.state.isReady, isFalse);
      expect(cubit.state.isRecording, isFalse);
    });
  });

  group('permissions', () {
    test('a refusal leaves a retryable state, not a failure', () async {
      final CameraCubit cubit = build(permission: CapturePermissionStatus.denied);
      addTearDown(cubit.close);

      await cubit.start();

      expect(cubit.state.status, CameraStatus.permissionDenied);
      expect(cubit.state.needsPermission, isTrue);
      expect(cubit.state.controller, isNull);
    });

    test('a permanent refusal is distinguished, so the UI can offer settings', () async {
      final CameraCubit cubit = build(
        permission: CapturePermissionStatus.permanentlyDenied,
      );
      addTearDown(cubit.close);

      await cubit.start();

      expect(cubit.state.status, CameraStatus.permissionPermanentlyDenied);
      expect(cubit.state.needsPermission, isTrue);
    });

    test('backgrounding during the prompt does not abandon the request', () async {
      final CameraCubit cubit = build();
      addTearDown(cubit.close);

      // Android pauses the activity behind the permission sheet; the cubit must
      // ignore that rather than tear down mid-handshake.
      final Future<void> starting = cubit.start();
      await cubit.releaseCamera();
      await starting;

      expect(cubit.state.status, isNot(CameraStatus.initializing));
    });
  });

  group('camera start failure', () {
    test('is reported as a message the screen can show', () async {
      final CameraCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.start();

      expect(cubit.state.status, CameraStatus.failure);
      expect(cubit.state.errorMessage, 'This device has no camera available.');
      expect(cubit.state.controller, isNull);
    });
  });

  group('hardware faults after start', () {
    test('are wired up, so a dead sensor cannot go unnoticed', () {
      final CameraCubit cubit = build();
      addTearDown(cubit.close);

      expect(cameraService.onDeviceError, isNotNull);
    });

    test('drop the preview and offer the reason, rather than freezing on a frame', () {
      final CameraCubit cubit = build();
      addTearDown(cubit.close);

      // What a HAL crash looks like from Dart: the controller reports an error
      // after having started successfully.
      cameraService.onDeviceError!('The camera device has encountered a serious error');

      expect(cubit.state.status, CameraStatus.failure);
      expect(
        cubit.state.errorMessage,
        'The camera device has encountered a serious error',
      );
      expect(cubit.state.controller, isNull);
      // The shutter must not be left mid-take, or it stays disabled forever.
      expect(cubit.state.recordingStatus, RecordingStatus.idle);
      expect(cubit.state.elapsed, Duration.zero);
      expect(cubit.state.isRecording, isFalse);
    });
  });

  group('filter selection', () {
    test('records the chosen look', () {
      final CameraCubit cubit = build();
      addTearDown(cubit.close);

      cubit.selectFilter(FilterPresets.vintage);
      expect(cubit.state.filter, FilterPresets.vintage);
    });

    test('re-selecting the active look emits nothing', () {
      final CameraCubit cubit = build();
      addTearDown(cubit.close);

      final List<CameraState> emitted = <CameraState>[];
      final subscription = cubit.stream.listen(emitted.add);
      addTearDown(subscription.cancel);

      cubit.selectFilter(FilterPresets.original);

      expect(emitted, isEmpty);
    });
  });

  group('one-off messages', () {
    test('clearing a null notice emits nothing', () {
      final CameraCubit cubit = build();
      addTearDown(cubit.close);

      final List<CameraState> emitted = <CameraState>[];
      final subscription = cubit.stream.listen(emitted.add);
      addTearDown(subscription.cancel);

      cubit.clearNotice();
      cubit.clearLastRecording();

      expect(emitted, isEmpty);
    });
  });

  group('controls are inert until the camera is live', () {
    test('zoom, focus, flash and the shutter all no-op', () async {
      final CameraCubit cubit = build();
      addTearDown(cubit.close);

      final CameraState before = cubit.state;
      await cubit.setZoom(4);
      await cubit.toggleFlash();
      await cubit.switchLens();
      await cubit.toggleRecording();

      expect(cubit.state, equals(before));
    });
  });

  group('recording progress', () {
    test('is the fraction of the one-minute ceiling used', () {
      expect(CameraState().recordingProgress, 0);
      expect(
        CameraState(elapsed: RecordingLimits.maxDuration * 0.5).recordingProgress,
        closeTo(0.5, 0.001),
      );
    });

    test('is clamped, so an overrun cannot draw past a full ring', () {
      expect(
        CameraState(elapsed: RecordingLimits.maxDuration * 2).recordingProgress,
        1,
      );
    });
  });
}
