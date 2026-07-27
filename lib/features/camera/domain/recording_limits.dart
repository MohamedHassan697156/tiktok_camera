/// Timing rules for a single take.
abstract final class RecordingLimits {
  /// Longest clip the camera will record before stopping itself.
  ///
  /// A hard ceiling keeps a forgotten recording from filling the device, and
  /// matches the one-minute take the UI's progress ring is drawn against.
  static const Duration maxDuration = Duration(seconds: 60);

  /// Shortest clip worth keeping.
  ///
  /// Stopping within a few frames of starting usually means a double tap rather
  /// than an intended take, and the encoder often has not written a playable
  /// moov atom yet, so such clips are discarded with a nudge instead of saved
  /// broken.
  static const Duration minDuration = Duration(milliseconds: 400);

  /// How often the elapsed time is refreshed while recording.
  ///
  /// Ten times a second is smooth enough for the progress ring without waking
  /// the UI on every frame.
  static const Duration tick = Duration(milliseconds: 100);
}
