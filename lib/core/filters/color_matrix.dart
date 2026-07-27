import 'dart:ui' show ColorFilter;

import 'package:flutter/foundation.dart';

/// An immutable 4x5 colour matrix — the transform accepted by
/// [ColorFilter.matrix].
///
/// Storage is row-major with one row per output channel:
///
/// ```text
/// R' = m[ 0]*R + m[ 1]*G + m[ 2]*B + m[ 3]*A + m[ 4]
/// G' = m[ 5]*R + m[ 6]*G + m[ 7]*B + m[ 8]*A + m[ 9]
/// B' = m[10]*R + m[11]*G + m[12]*B + m[13]*A + m[14]
/// A' = m[15]*R + m[16]*G + m[17]*B + m[18]*A + m[19]
/// ```
///
/// The four multiplier columns act on normalised channel values, while the
/// translation column (index 4 of each row) is expressed on the 0-255 scale.
/// That asymmetry is [ColorFilter.matrix]'s contract, not ours.
///
/// Every filter in the app is built by composing the named factories below with
/// [then], which keeps the individual adjustments readable and lets the GPU
/// collapse a whole look into a single matrix.
@immutable
class ColorMatrix {
  /// Wraps 20 pre-computed coefficients.
  const ColorMatrix(this.storage) : assert(storage.length == 20, 'expected 4x5 = 20 values');

  /// The identity transform: output equals input.
  static final ColorMatrix identity = ColorMatrix(<double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  /// Rec. 709 luminance weights, used wherever a channel mix needs to preserve
  /// perceived brightness.
  static const double _lumR = 0.2126;
  static const double _lumG = 0.7152;
  static const double _lumB = 0.0722;

  /// The 20 coefficients, row-major.
  final List<double> storage;

  /// Scales colour saturation. `0` is fully desaturated, `1` is unchanged,
  /// values above `1` push saturation further.
  factory ColorMatrix.saturation(double amount) {
    final double inv = 1 - amount;
    final double r = inv * _lumR;
    final double g = inv * _lumG;
    final double b = inv * _lumB;
    return ColorMatrix(<double>[
      r + amount, g, b, 0, 0, //
      r, g + amount, b, 0, 0, //
      r, g, b + amount, 0, 0, //
      0, 0, 0, 1, 0, //
    ]);
  }

  /// Removes colour while preserving luminance. `0` keeps the original colours,
  /// `1` is a full black-and-white conversion.
  factory ColorMatrix.grayscale(double amount) => ColorMatrix.saturation(1 - amount);

  /// Expands or compresses tonal range around mid-grey. `1` is unchanged.
  factory ColorMatrix.contrast(double amount) {
    // Pivot around 0.5 in normalised space, i.e. 127.5 on the 0-255 translation
    // scale, so mid-grey stays put while highlights and shadows spread.
    final double pivot = 127.5 * (1 - amount);
    return ColorMatrix(<double>[
      amount, 0, 0, 0, pivot, //
      0, amount, 0, 0, pivot, //
      0, 0, amount, 0, pivot, //
      0, 0, 0, 1, 0, //
    ]);
  }

  /// Adds a flat offset to every colour channel, lifting or dropping the whole
  /// image. [delta] is on the 0-255 scale; `0` is unchanged.
  factory ColorMatrix.brightness(double delta) {
    return ColorMatrix(<double>[
      1, 0, 0, 0, delta, //
      0, 1, 0, 0, delta, //
      0, 0, 1, 0, delta, //
      0, 0, 0, 1, 0, //
    ]);
  }

  /// Multiplies every colour channel by [gain], the way an exposure stop does.
  /// `1` is unchanged.
  factory ColorMatrix.exposure(double gain) {
    return ColorMatrix(<double>[
      gain, 0, 0, 0, 0, //
      0, gain, 0, 0, 0, //
      0, 0, gain, 0, 0, //
      0, 0, 0, 1, 0, //
    ]);
  }

  /// Shifts white balance along the blue-amber axis. Positive [amount] warms
  /// the image (more red, less blue), negative cools it. Useful range is
  /// `-1..1`; `0` is unchanged.
  factory ColorMatrix.temperature(double amount) {
    const double strength = 0.25;
    return ColorMatrix(<double>[
      1 + strength * amount, 0, 0, 0, 0, //
      0, 1 + strength * amount * 0.15, 0, 0, 0, //
      0, 0, 1 - strength * amount, 0, 0, //
      0, 0, 0, 1, 0, //
    ]);
  }

  /// Shifts white balance along the green-magenta axis. Positive [amount] adds
  /// green, negative adds magenta. Useful range is `-1..1`; `0` is unchanged.
  factory ColorMatrix.tint(double amount) {
    const double strength = 0.2;
    return ColorMatrix(<double>[
      1 - strength * amount * 0.5, 0, 0, 0, 0, //
      0, 1 + strength * amount, 0, 0, 0, //
      0, 0, 1 - strength * amount * 0.5, 0, 0, //
      0, 0, 0, 1, 0, //
    ]);
  }

  /// Blends towards the classic sepia channel mix. `0` keeps the original
  /// colours, `1` is full sepia.
  factory ColorMatrix.sepia(double amount) {
    return ColorMatrix.lerp(identity, _fullSepia, amount);
  }

  static final ColorMatrix _fullSepia = ColorMatrix(<double>[
    0.393, 0.769, 0.189, 0, 0, //
    0.349, 0.686, 0.168, 0, 0, //
    0.272, 0.534, 0.131, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  /// Linearly interpolates coefficient-wise between [a] and [b].
  ///
  /// Interpolating the coefficients is not the same as interpolating the images
  /// the two matrices produce, but for the adjustments used here the difference
  /// is invisible and it keeps intensity blending a single cheap operation.
  ///
  /// The endpoints are returned as-is rather than computed. `a + (b - a) * 1`
  /// lands a fraction of a bit away from `b` in floating point, and callers rely
  /// on exact equality: [isIdentity] is what lets a finished fade drop its filter
  /// layer entirely, and widget diffing skips rebuilds on equal matrices.
  static ColorMatrix lerp(ColorMatrix a, ColorMatrix b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;

    final List<double> out = List<double>.filled(20, 0);
    for (int i = 0; i < 20; i++) {
      out[i] = a.storage[i] + (b.storage[i] - a.storage[i]) * t;
    }
    return ColorMatrix(out);
  }

  /// Returns the matrix equivalent to applying `this` and then [next].
  ///
  /// Both operands are affine (a 4x4 linear part plus a translation), so the
  /// composition is `linear = next.linear * this.linear` and
  /// `offset = next.linear * this.offset + next.offset`.
  ColorMatrix then(ColorMatrix next) {
    final List<double> first = storage;
    final List<double> second = next.storage;
    final List<double> out = List<double>.filled(20, 0);

    for (int row = 0; row < 4; row++) {
      for (int col = 0; col < 4; col++) {
        double sum = 0;
        for (int k = 0; k < 4; k++) {
          sum += second[row * 5 + k] * first[k * 5 + col];
        }
        out[row * 5 + col] = sum;
      }

      double offset = second[row * 5 + 4];
      for (int k = 0; k < 4; k++) {
        offset += second[row * 5 + k] * first[k * 5 + 4];
      }
      out[row * 5 + 4] = offset;
    }

    return ColorMatrix(out);
  }

  /// Scales this matrix's effect towards the identity. `0` disables the filter
  /// entirely, `1` applies it at full strength.
  ColorMatrix withIntensity(double intensity) => ColorMatrix.lerp(identity, this, intensity);

  /// Whether this matrix leaves pixels untouched, so callers can skip wrapping
  /// their subtree in a [ColorFilter] at all.
  bool get isIdentity => this == identity;

  /// The GPU-side filter for this matrix.
  ColorFilter toColorFilter() => ColorFilter.matrix(storage);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ColorMatrix && listEquals(other.storage, storage);
  }

  @override
  int get hashCode => Object.hashAll(storage);

  @override
  String toString() => 'ColorMatrix(${storage.map((double v) => v.toStringAsFixed(3)).join(', ')})';
}
