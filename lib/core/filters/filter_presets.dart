import 'color_matrix.dart';
import 'filter_preset.dart';

/// The catalogue of looks offered by the camera.
///
/// Each recipe is written as a chain of single-purpose adjustments rather than a
/// hand-tuned block of 20 numbers, so the intent behind a look stays legible and
/// can be nudged one term at a time. The chain is collapsed into one matrix at
/// construction, so a long recipe is no more expensive to render than a short
/// one.
abstract final class FilterPresets {
  /// No grading — the sensor image as it comes.
  static final FilterPreset original = FilterPreset(
    id: 'original',
    label: 'Original',
    matrix: ColorMatrix.identity,
  );

  /// Soft skin, warm cast, lifted shadows: the flattering default.
  ///
  /// The blur does the smoothing and the small contrast bump keeps it from
  /// reading as mushy.
  static final FilterPreset beauty = FilterPreset(
    id: 'beauty',
    label: 'Beauty',
    blurSigma: 1.4,
    matrix: ColorMatrix.temperature(0.18)
        .then(ColorMatrix.brightness(10))
        .then(ColorMatrix.saturation(1.06))
        .then(ColorMatrix.contrast(1.04)),
  );

  /// Luminance-correct monochrome with a firmer tonal curve.
  static final FilterPreset blackAndWhite = FilterPreset(
    id: 'mono',
    label: 'B&W',
    matrix: ColorMatrix.grayscale(1).then(ColorMatrix.contrast(1.14)),
  );

  /// Faded film: sepia channel mix, washed shadows, restrained colour.
  static final FilterPreset vintage = FilterPreset(
    id: 'vintage',
    label: 'Vintage',
    matrix: ColorMatrix.sepia(0.7)
        .then(ColorMatrix.saturation(0.9))
        .then(ColorMatrix.contrast(0.88))
        .then(ColorMatrix.brightness(12)),
  );

  /// Golden-hour cast with a little extra colour.
  static final FilterPreset warm = FilterPreset(
    id: 'warm',
    label: 'Warm',
    matrix: ColorMatrix.temperature(0.32)
        .then(ColorMatrix.saturation(1.1))
        .then(ColorMatrix.brightness(4)),
  );

  /// Blue-hour cast with crisper contrast.
  static final FilterPreset cool = FilterPreset(
    id: 'cool',
    label: 'Cool',
    matrix: ColorMatrix.temperature(-0.32)
        .then(ColorMatrix.saturation(1.05))
        .then(ColorMatrix.contrast(1.06)),
  );

  /// Punchy, high-saturation look for daylight scenes.
  static final FilterPreset vivid = FilterPreset(
    id: 'vivid',
    label: 'Vivid',
    matrix: ColorMatrix.saturation(1.42).then(ColorMatrix.contrast(1.12)),
  );

  /// Low-contrast matte finish with lifted blacks.
  static final FilterPreset fade = FilterPreset(
    id: 'fade',
    label: 'Fade',
    matrix: ColorMatrix.saturation(0.72)
        .then(ColorMatrix.contrast(0.82))
        .then(ColorMatrix.brightness(18)),
  );

  /// Every preset, in the order the filter tray shows them.
  static final List<FilterPreset> all = <FilterPreset>[
    original,
    beauty,
    blackAndWhite,
    vintage,
    warm,
    cool,
    vivid,
    fade,
  ];

  /// Looks up a preset by its persisted [FilterPreset.id], falling back to
  /// [original] for ids written by a build that no longer matches this one.
  static FilterPreset byId(String? id) {
    if (id == null) return original;
    for (final FilterPreset preset in all) {
      if (preset.id == id) return preset;
    }
    return original;
  }
}
