import 'package:flutter/foundation.dart';

/// A camera problem worth telling the user about, already reduced to a sentence
/// they can act on.
///
/// The plugin throws `CameraException`s whose codes are meaningful to us but not
/// to a user; the data layer translates them here so the presentation layer never
/// has to interpret a platform error string.
@immutable
class CameraFailure implements Exception {
  const CameraFailure(this.message, {this.cause});

  /// User-facing description.
  final String message;

  /// The original error, kept for logging.
  final Object? cause;

  @override
  String toString() => 'CameraFailure($message${cause == null ? '' : ', cause: $cause'})';
}
