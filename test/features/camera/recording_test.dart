import 'package:flutter_test/flutter_test.dart';
import 'package:tiktokcamera/core/filters/filter_presets.dart';
import 'package:tiktokcamera/features/camera/domain/recording.dart';

void main() {
  final DateTime recordedAt = DateTime.utc(2026, 7, 26, 14, 30, 12);

  Recording sample() => Recording(
    path: '/data/app/recordings/VID_20260726_143012.mp4',
    duration: const Duration(seconds: 9, milliseconds: 400),
    recordedAt: recordedAt,
    filterId: FilterPresets.vintage.id,
  );

  group('serialisation', () {
    test('round-trips through the sidecar format', () {
      final Recording original = sample();
      final Recording restored = Recording.fromJson(
        original.toJson(),
        path: original.path,
      );
      expect(restored, equals(original));
    });

    test('does not store the path, which comes from the file it sits beside', () {
      expect(sample().toJson().containsKey('path'), isFalse);
    });

    test('keeps millisecond precision on the duration', () {
      final Recording restored = Recording.fromJson(sample().toJson(), path: '/x.mp4');
      expect(restored.duration.inMilliseconds, 9400);
    });
  });

  group('tolerant parsing', () {
    test('an empty sidecar yields a playable clip with neutral defaults', () {
      final Recording restored = Recording.fromJson(
        <String, dynamic>{},
        path: '/x.mp4',
      );
      expect(restored.path, '/x.mp4');
      expect(restored.duration, Duration.zero);
      expect(restored.filter, FilterPresets.original);
    });

    test('an unparseable timestamp does not throw', () {
      final Recording restored = Recording.fromJson(
        <String, dynamic>{'recordedAt': 'not a date', 'durationMs': 500},
        path: '/x.mp4',
      );
      expect(restored.recordedAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(restored.duration, const Duration(milliseconds: 500));
    });
  });

  group('filter resolution', () {
    test('resolves the stored id to its preset', () {
      expect(sample().filter, FilterPresets.vintage);
    });

    test('falls back to original for a look this build no longer has', () {
      final Recording restored = Recording.fromJson(
        <String, dynamic>{'filterId': 'retired-look'},
        path: '/x.mp4',
      );
      expect(restored.filter, FilterPresets.original);
    });
  });

  test('value equality covers every field', () {
    expect(sample(), equals(sample()));
    expect(sample().hashCode, equals(sample().hashCode));

    final Recording differentFilter = Recording(
      path: sample().path,
      duration: sample().duration,
      recordedAt: recordedAt,
      filterId: FilterPresets.warm.id,
    );
    expect(sample(), isNot(equals(differentFilter)));
  });
}
