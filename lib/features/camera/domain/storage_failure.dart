import 'package:flutter/foundation.dart';

/// A problem saving, listing or exporting a clip, reduced to a sentence the user
/// can act on.
@immutable
class StorageFailure implements Exception {
  const StorageFailure(this.message, {this.cause});

  /// User-facing description.
  final String message;

  /// The original error, kept for logging.
  final Object? cause;

  @override
  String toString() => 'StorageFailure($message${cause == null ? '' : ', cause: $cause'})';
}
