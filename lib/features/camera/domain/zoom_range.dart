import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// The zoom factors a particular sensor supports.
///
/// Ranges differ per lens, so this is re-read every time the active camera
/// changes rather than assumed.
@immutable
class ZoomRange {
  const ZoomRange({required this.min, required this.max});

  /// Neutral range used before a camera reports its real capabilities.
  static const ZoomRange none = ZoomRange(min: 1, max: 1);

  final double min;
  final double max;

  /// Whether the sensor can zoom at all, i.e. whether the zoom control is worth
  /// showing.
  bool get isSupported => max > min + 0.01;

  /// Clamps [level] into this range.
  double clamp(double level) => math.min(math.max(level, min), max);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ZoomRange && other.min == min && other.max == max;
  }

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'ZoomRange($min..$max)';
}
