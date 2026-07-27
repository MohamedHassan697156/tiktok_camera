import 'package:flutter_test/flutter_test.dart';
import 'package:tiktokcamera/core/utils/duration_format.dart';

void main() {
  group('asClock', () {
    test('pads to a fixed width so the timer does not shift', () {
      expect(Duration.zero.asClock, '00:00');
      expect(const Duration(seconds: 7).asClock, '00:07');
      expect(const Duration(seconds: 65).asClock, '01:05');
      expect(const Duration(minutes: 10, seconds: 9).asClock, '10:09');
    });

    test('wraps minutes at the hour rather than counting past 59', () {
      expect(const Duration(hours: 1, minutes: 2, seconds: 3).asClock, '02:03');
    });
  });

  group('asShortClock', () {
    test('drops the leading zero on minutes', () {
      expect(Duration.zero.asShortClock, '0:00');
      expect(const Duration(seconds: 7).asShortClock, '0:07');
      expect(const Duration(seconds: 65).asShortClock, '1:05');
    });
  });
}
