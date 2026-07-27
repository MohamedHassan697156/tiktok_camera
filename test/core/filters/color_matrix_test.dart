import 'package:flutter_test/flutter_test.dart';
import 'package:tiktokcamera/core/filters/color_matrix.dart';

/// Applies [matrix] to an RGBA colour expressed on the 0-255 scale.
///
/// This mirrors what the compositor does, and is the reference the tests measure
/// the matrix factories against: asserting on raw coefficients would only restate
/// the implementation, whereas asserting on transformed pixels checks the maths
/// actually does what the doc comments claim.
List<double> _apply(ColorMatrix matrix, List<double> rgba) {
  final List<double> m = matrix.storage;
  final List<double> out = <double>[];
  for (int row = 0; row < 4; row++) {
    double value = m[row * 5 + 4];
    for (int channel = 0; channel < 4; channel++) {
      value += m[row * 5 + channel] * rgba[channel];
    }
    out.add(value);
  }
  return out;
}

Matcher _closeToAll(List<double> expected) => pairwiseCompare<double, double>(
  expected,
  (double actual, double want) => (actual - want).abs() < 0.001,
  'is within 0.001 of',
);

void main() {
  const List<double> midGrey = <double>[127.5, 127.5, 127.5, 255];
  const List<double> skin = <double>[210, 160, 130, 255];

  group('identity', () {
    test('leaves a colour untouched', () {
      expect(_apply(ColorMatrix.identity, skin), _closeToAll(skin));
    });

    test('reports itself as the identity', () {
      expect(ColorMatrix.identity.isIdentity, isTrue);
      expect(ColorMatrix.saturation(1).isIdentity, isTrue);
      expect(ColorMatrix.saturation(0).isIdentity, isFalse);
    });
  });

  group('saturation', () {
    test('at 0 collapses every channel to the same luminance', () {
      final List<double> result = _apply(ColorMatrix.saturation(0), skin);
      final double luminance = 0.2126 * 210 + 0.7152 * 160 + 0.0722 * 130;
      expect(result[0], closeTo(luminance, 0.001));
      expect(result[1], closeTo(luminance, 0.001));
      expect(result[2], closeTo(luminance, 0.001));
    });

    test('preserves grey, which has no colour to scale', () {
      expect(_apply(ColorMatrix.saturation(1.8), midGrey), _closeToAll(midGrey));
    });

    test('pushes a colour further from grey above 1', () {
      final List<double> boosted = _apply(ColorMatrix.saturation(1.5), skin);
      // Red was the dominant channel, so boosting saturation must raise it.
      expect(boosted[0], greaterThan(210));
      expect(boosted[2], lessThan(130));
    });
  });

  test('grayscale is saturation inverted', () {
    expect(
      _apply(ColorMatrix.grayscale(1), skin),
      _closeToAll(_apply(ColorMatrix.saturation(0), skin)),
    );
    expect(ColorMatrix.grayscale(0).isIdentity, isTrue);
  });

  group('contrast', () {
    test('pivots around mid-grey, leaving it in place', () {
      expect(_apply(ColorMatrix.contrast(1.6), midGrey), _closeToAll(midGrey));
    });

    test('pushes a bright value brighter and a dark value darker', () {
      final ColorMatrix boosted = ColorMatrix.contrast(1.5);
      expect(_apply(boosted, <double>[200, 200, 200, 255])[0], greaterThan(200));
      expect(_apply(boosted, <double>[50, 50, 50, 255])[0], lessThan(50));
    });
  });

  test('brightness offsets colour channels but not alpha', () {
    final List<double> result = _apply(ColorMatrix.brightness(20), skin);
    expect(result, _closeToAll(<double>[230, 180, 150, 255]));
  });

  test('exposure scales colour channels but not alpha', () {
    final List<double> result = _apply(ColorMatrix.exposure(0.5), skin);
    expect(result, _closeToAll(<double>[105, 80, 65, 255]));
  });

  group('temperature', () {
    test('warming raises red and lowers blue', () {
      final List<double> warmed = _apply(ColorMatrix.temperature(0.5), midGrey);
      expect(warmed[0], greaterThan(midGrey[0]));
      expect(warmed[2], lessThan(midGrey[2]));
    });

    test('cooling does the opposite', () {
      final List<double> cooled = _apply(ColorMatrix.temperature(-0.5), midGrey);
      expect(cooled[0], lessThan(midGrey[0]));
      expect(cooled[2], greaterThan(midGrey[2]));
    });

    test('is neutral at 0', () {
      expect(ColorMatrix.temperature(0).isIdentity, isTrue);
    });
  });

  test('tint at 0 is neutral, and positive tint raises green', () {
    expect(ColorMatrix.tint(0).isIdentity, isTrue);
    expect(_apply(ColorMatrix.tint(0.5), midGrey)[1], greaterThan(midGrey[1]));
  });

  group('sepia', () {
    test('is neutral at 0', () {
      expect(ColorMatrix.sepia(0).isIdentity, isTrue);
    });

    test('at 1 tints towards amber: red above green above blue', () {
      final List<double> result = _apply(ColorMatrix.sepia(1), midGrey);
      expect(result[0], greaterThan(result[1]));
      expect(result[1], greaterThan(result[2]));
    });
  });

  group('then', () {
    test('composes in application order, including translations', () {
      final ColorMatrix brighten = ColorMatrix.brightness(20);
      final ColorMatrix halve = ColorMatrix.exposure(0.5);

      // Brightening first then halving must halve the added offset too; doing it
      // the other way round must not. This is the case a naive
      // multiply-the-linear-parts composition gets wrong.
      expect(
        _apply(brighten.then(halve), skin),
        _closeToAll(_apply(halve, _apply(brighten, skin))),
      );
      expect(
        _apply(halve.then(brighten), skin),
        _closeToAll(_apply(brighten, _apply(halve, skin))),
      );
      expect(
        _apply(brighten.then(halve), skin),
        isNot(_closeToAll(_apply(halve.then(brighten), skin))),
      );
    });

    test('matches sequential application for a four-step recipe', () {
      final ColorMatrix a = ColorMatrix.temperature(0.3);
      final ColorMatrix b = ColorMatrix.brightness(12);
      final ColorMatrix c = ColorMatrix.saturation(1.2);
      final ColorMatrix d = ColorMatrix.contrast(0.9);

      final List<double> stepwise = _apply(
        d,
        _apply(c, _apply(b, _apply(a, skin))),
      );
      expect(_apply(a.then(b).then(c).then(d), skin), _closeToAll(stepwise));
    });

    test('composing with the identity changes nothing', () {
      final ColorMatrix look = ColorMatrix.sepia(0.6);
      expect(look.then(ColorMatrix.identity), equals(look));
      expect(ColorMatrix.identity.then(look), equals(look));
    });
  });

  group('lerp and withIntensity', () {
    test('lerp returns the endpoints at 0 and 1', () {
      final ColorMatrix mono = ColorMatrix.grayscale(1);
      expect(ColorMatrix.lerp(ColorMatrix.identity, mono, 0), equals(ColorMatrix.identity));
      expect(ColorMatrix.lerp(ColorMatrix.identity, mono, 1), equals(mono));
    });

    test('withIntensity scales a look back towards no-op', () {
      final ColorMatrix mono = ColorMatrix.grayscale(1);
      expect(mono.withIntensity(0).isIdentity, isTrue);
      expect(mono.withIntensity(1), equals(mono));

      // Half-strength monochrome must sit between the colour and the grey.
      final List<double> half = _apply(mono.withIntensity(0.5), skin);
      final List<double> full = _apply(mono, skin);
      expect(half[0], greaterThan(full[0]));
      expect(half[0], lessThan(skin[0]));
    });
  });

  group('value semantics', () {
    test('equal coefficients compare equal and hash alike', () {
      final ColorMatrix a = ColorMatrix.contrast(1.2);
      final ColorMatrix b = ColorMatrix.contrast(1.2);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(ColorMatrix.contrast(1.3))));
    });

    test('rejects a wrong-sized coefficient list', () {
      expect(() => ColorMatrix(List<double>.filled(19, 0)), throwsA(isA<AssertionError>()));
    });
  });
}
