import 'package:flutter_test/flutter_test.dart';
import 'package:tiktokcamera/core/filters/filter_preset.dart';
import 'package:tiktokcamera/core/filters/filter_presets.dart';

void main() {
  group('catalogue', () {
    test('ids are unique, because they are the persisted key', () {
      final Set<String> ids = FilterPresets.all.map((FilterPreset p) => p.id).toSet();
      expect(ids.length, FilterPresets.all.length);
    });

    test('every preset has a label to show in the tray', () {
      for (final FilterPreset preset in FilterPresets.all) {
        expect(preset.label, isNotEmpty, reason: '${preset.id} has no label');
      }
    });

    test('original leads the list and is a pass-through', () {
      expect(FilterPresets.all.first, FilterPresets.original);
      expect(FilterPresets.original.isPassthrough, isTrue);
    });

    test('every other preset actually changes the image', () {
      for (final FilterPreset preset in FilterPresets.all.skip(1)) {
        expect(
          preset.isPassthrough,
          isFalse,
          reason: '${preset.id} would render identically to original',
        );
      }
    });

    test('only the beauty look pays for a blur pass', () {
      for (final FilterPreset preset in FilterPresets.all) {
        if (preset.id == FilterPresets.beauty.id) {
          expect(preset.blurSigma, greaterThan(0));
        } else {
          expect(preset.blurSigma, 0, reason: '${preset.id} should not blur');
        }
      }
    });

    test('the brief is covered: beauty, mono, vintage, warm and cool all exist', () {
      final Set<String> ids = FilterPresets.all.map((FilterPreset p) => p.id).toSet();
      expect(ids, containsAll(<String>['beauty', 'mono', 'vintage', 'warm', 'cool']));
    });
  });

  group('byId', () {
    test('round-trips every preset', () {
      for (final FilterPreset preset in FilterPresets.all) {
        expect(FilterPresets.byId(preset.id), same(preset));
      }
    });

    test('falls back to original for ids this build does not know', () {
      // Clips recorded by an older build must still play rather than disappear.
      expect(FilterPresets.byId('a-look-we-removed'), FilterPresets.original);
      expect(FilterPresets.byId(''), FilterPresets.original);
      expect(FilterPresets.byId(null), FilterPresets.original);
    });
  });

  group('value semantics', () {
    test('presets compare by content', () {
      final FilterPreset copy = FilterPreset(
        id: FilterPresets.warm.id,
        label: FilterPresets.warm.label,
        matrix: FilterPresets.warm.matrix,
        blurSigma: FilterPresets.warm.blurSigma,
      );
      expect(copy, equals(FilterPresets.warm));
      expect(copy.hashCode, equals(FilterPresets.warm.hashCode));
      expect(FilterPresets.warm, isNot(equals(FilterPresets.cool)));
    });
  });
}
