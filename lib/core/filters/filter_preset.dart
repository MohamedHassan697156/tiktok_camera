import 'package:flutter/foundation.dart';

import 'color_matrix.dart';

/// A named camera look: a colour grade plus an optional softening pass.
///
/// A preset is pure data. It is applied to the live preview, to playback of a
/// finished recording, and to the swatch in the filter tray by the same widget,
/// so those three surfaces cannot drift apart.
@immutable
class FilterPreset {
  const FilterPreset({
    required this.id,
    required this.label,
    required this.matrix,
    this.blurSigma = 0,
  });

  /// Stable identifier, persisted alongside a recording so the gallery can
  /// replay it with the look it was shot with. Never localise this.
  final String id;

  /// Human-readable name shown in the filter tray.
  final String label;

  /// The colour grade.
  final ColorMatrix matrix;

  /// Gaussian blur applied underneath the colour grade, in logical pixels.
  ///
  /// Only the beauty look uses this; everything else grades colour alone and so
  /// costs nothing beyond the single matrix the compositor already applies.
  final double blurSigma;

  /// Whether this preset leaves the image untouched, letting callers skip the
  /// filter layers entirely.
  bool get isPassthrough => matrix.isIdentity && blurSigma == 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FilterPreset &&
        other.id == id &&
        other.label == label &&
        other.matrix == matrix &&
        other.blurSigma == blurSigma;
  }

  @override
  int get hashCode => Object.hash(id, label, matrix, blurSigma);

  @override
  String toString() => 'FilterPreset($id)';
}
