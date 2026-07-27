import 'package:permission_handler/permission_handler.dart';

/// Outcome of asking for the permissions a video camera needs.
enum CapturePermissionStatus {
  /// Both camera and microphone are available.
  granted,

  /// Refused this time; asking again will show the system prompt again.
  denied,

  /// Refused permanently (or blocked by policy). Only the system settings screen
  /// can change this, so the UI must deep-link there instead of re-prompting.
  permanentlyDenied,
}

/// Requests the camera and microphone permissions as a single unit.
///
/// They are treated as one because a video clip with no audio is not the feature
/// we advertise — partial success would leave the user with a camera that
/// silently records silence.
class CapturePermissionService {
  const CapturePermissionService();

  static const List<Permission> _required = <Permission>[
    Permission.camera,
    Permission.microphone,
  ];

  /// Prompts for anything not yet granted and reports the combined result.
  Future<CapturePermissionStatus> request() async {
    final Map<Permission, PermissionStatus> results = await _required.request();
    return _combine(results.values);
  }

  /// Reports the current state without prompting, for the resume path where the
  /// user may have just granted access in system settings.
  Future<CapturePermissionStatus> check() async {
    final List<PermissionStatus> statuses = <PermissionStatus>[];
    for (final Permission permission in _required) {
      statuses.add(await permission.status);
    }
    return _combine(statuses);
  }

  /// Opens the app's entry in system settings. Returns whether it opened.
  Future<bool> openSettings() => openAppSettings();

  /// Collapses per-permission statuses into the worst outcome, so a single
  /// refusal is never mistaken for success.
  CapturePermissionStatus _combine(Iterable<PermissionStatus> statuses) {
    if (statuses.every((PermissionStatus status) => status.isGranted || status.isLimited)) {
      return CapturePermissionStatus.granted;
    }
    final bool blocked = statuses.any(
      (PermissionStatus status) => status.isPermanentlyDenied || status.isRestricted,
    );
    return blocked ? CapturePermissionStatus.permanentlyDenied : CapturePermissionStatus.denied;
  }
}
