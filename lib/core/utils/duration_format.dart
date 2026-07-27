/// Clock formatting for the recording HUD and the gallery.
extension DurationFormat on Duration {
  /// Zero-padded `mm:ss`, e.g. `00:07`.
  ///
  /// Used while recording, where a fixed width keeps the timer from shifting
  /// sideways as the digits change.
  String get asClock {
    final String minutes = inMinutes.remainder(60).toString().padLeft(2, '0');
    final String seconds = inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// Compact `m:ss`, e.g. `0:07`, for labelling a finished clip.
  String get asShortClock {
    final String seconds = inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${inMinutes.remainder(60)}:$seconds';
  }
}
