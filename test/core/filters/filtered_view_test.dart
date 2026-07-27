import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiktokcamera/core/filters/filtered_view.dart';
import 'package:tiktokcamera/core/filters/filter_presets.dart';

void main() {
  const Key childKey = Key('graded-child');

  Future<void> pump(WidgetTester tester, Widget widget) =>
      tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: widget));

  group('FilteredView', () {
    testWidgets('adds no render layers for the neutral look', (WidgetTester tester) async {
      await pump(
        tester,
        FilteredView(
          preset: FilterPresets.original,
          child: const SizedBox(key: childKey),
        ),
      );

      // A pass-through preset must not pay for a save-layer it does not need.
      expect(find.byType(ColorFiltered), findsNothing);
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byKey(childKey), findsOneWidget);
    });

    testWidgets('grades with a colour filter only', (WidgetTester tester) async {
      await pump(
        tester,
        FilteredView(
          preset: FilterPresets.blackAndWhite,
          child: const SizedBox(key: childKey),
        ),
      );

      expect(find.byType(ColorFiltered), findsOneWidget);
      expect(find.byType(ImageFiltered), findsNothing);
    });

    testWidgets('softens and grades for the beauty look', (WidgetTester tester) async {
      await pump(
        tester,
        FilteredView(
          preset: FilterPresets.beauty,
          child: const SizedBox(key: childKey),
        ),
      );

      expect(find.byType(ImageFiltered), findsOneWidget);
      expect(find.byType(ColorFiltered), findsOneWidget);

      // Blur underneath, grade on top: grading a blurred image, not the reverse.
      final Finder colour = find.byType(ColorFiltered);
      expect(
        find.descendant(of: colour, matching: find.byType(ImageFiltered)),
        findsOneWidget,
      );
    });
  });

  group('AnimatedFilteredView', () {
    testWidgets('cross-fades between looks instead of snapping', (WidgetTester tester) async {
      Widget wrap(Widget child) =>
          Directionality(textDirection: TextDirection.ltr, child: child);

      await tester.pumpWidget(
        wrap(
          AnimatedFilteredView(
            preset: FilterPresets.original,
            child: const SizedBox(key: childKey),
          ),
        ),
      );

      await tester.pumpWidget(
        wrap(
          AnimatedFilteredView(
            preset: FilterPresets.blackAndWhite,
            child: const SizedBox(key: childKey),
          ),
        ),
      );

      // Part-way through, the matrix must be neither endpoint.
      await tester.pump(const Duration(milliseconds: 120));
      final ColorFiltered midway = tester.widget<ColorFiltered>(find.byType(ColorFiltered));

      await tester.pump(const Duration(milliseconds: 400));
      final ColorFiltered settled = tester.widget<ColorFiltered>(find.byType(ColorFiltered));

      expect(midway.colorFilter, isNot(equals(settled.colorFilter)));
      expect(
        settled.colorFilter,
        equals(FilterPresets.blackAndWhite.matrix.toColorFilter()),
      );
    });
  });

  group('ColorMatrixTween', () {
    test('interpolates between two looks', () {
      final ColorMatrixTween tween = ColorMatrixTween(
        begin: FilterPresets.original.matrix,
        end: FilterPresets.vintage.matrix,
      );

      expect(tween.lerp(0), equals(FilterPresets.original.matrix));
      expect(tween.lerp(1), equals(FilterPresets.vintage.matrix));
      expect(tween.lerp(0.5), isNot(equals(FilterPresets.original.matrix)));
    });
  });
}
