import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_freely/core/core.dart';

import '../fakes.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('dayPartFor', () {
    DateTime at(int h, [int m = 0]) => DateTime(2026, 11, 12, h, m);

    test('morning is 05:00 to 11:59', () {
      expect(dayPartFor(at(5)), DayPart.morning);
      expect(dayPartFor(at(11, 59)), DayPart.morning);
    });
    test('afternoon is 12:00 to 16:59', () {
      expect(dayPartFor(at(12)), DayPart.afternoon);
      expect(dayPartFor(at(16, 59)), DayPart.afternoon);
    });
    test('evening is 17:00 to 20:59', () {
      expect(dayPartFor(at(17)), DayPart.evening);
      expect(dayPartFor(at(20, 59)), DayPart.evening);
    });
    test('midnight covers 21:00 through 04:59, across the date change', () {
      expect(dayPartFor(at(21)), DayPart.midnight);
      expect(dayPartFor(at(0)), DayPart.midnight);
      expect(dayPartFor(at(4, 59)), DayPart.midnight);
    });
  });

  group('DayPartCard', () {
    for (final c in const [
      (8, 'Good morning', 'Rise and drive'),
      (14, 'Good afternoon', 'Bright hours ahead'),
      (19, 'Good evening', 'Golden hour rides'),
      (23, 'Good night', 'Late-night trips, safely home'),
    ]) {
      testWidgets('${c.$1}:00 greets with "${c.$2}"', (t) async {
        reduceMotionFor(t);
        await t.pumpWidget(_wrap(DayPartCard(name: 'Asha Rao', now: DateTime(2026, 11, 12, c.$1))));
        expect(find.text('${c.$2}, Asha'), findsOneWidget);
        expect(find.text(c.$3), findsOneWidget);
      });
    }

    testWidgets('a missing name still gives a greeting', (t) async {
      reduceMotionFor(t);
      await t.pumpWidget(_wrap(DayPartCard(name: '', now: DateTime(2026, 11, 12, 8))));
      expect(find.text('Good morning'), findsOneWidget);
    });

    testWidgets('the scene animates and stops when reduced motion is on', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_wrap(DayPartCard(name: 'Asha', now: DateTime(2026, 11, 12, 8))));
      await t.pump(const Duration(seconds: 1));
      expect(t.binding.hasScheduledFrame, isTrue); // continuous scene animation
      await t.pumpWidget(const SizedBox());

      reduceMotionFor(t);
      await t.pumpWidget(_wrap(DayPartCard(name: 'Asha', now: DateTime(2026, 11, 12, 8))));
      await t.pumpAndSettle();
      expect(t.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('fits a small phone with large text', (t) async {
      reduceMotionFor(t, size: const Size(320, 568));
      await t.pumpWidget(MaterialApp(
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.6)), child: w!),
        home: Scaffold(body: DayPartCard(name: 'Bhuvaneshwari Venkataraman', now: DateTime(2026, 11, 12, 23))),
      ));
      expect(t.takeException(), isNull);
    });
  });

  group('FloatingIconsBackground', () {
    testWidgets('shows the child over drifting icons', (t) async {
      reduceMotionFor(t);
      await t.pumpWidget(_wrap(const FloatingIconsBackground(child: Text('content'))));
      expect(find.text('content'), findsOneWidget);
      expect(find.byKey(const Key('floating_icons')), findsOneWidget);
    });

    testWidgets('icons drift over time and hold still under reduced motion', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_wrap(const FloatingIconsBackground(child: SizedBox.expand())));
      await t.pump(const Duration(seconds: 1));
      expect(t.binding.hasScheduledFrame, isTrue);
      await t.pumpWidget(const SizedBox());

      reduceMotionFor(t);
      await t.pumpWidget(_wrap(const FloatingIconsBackground(child: SizedBox.expand())));
      await t.pumpAndSettle();
      expect(t.binding.hasScheduledFrame, isFalse);
    });
  });

  testWidgets('GradientIconTile shows its icon and responds to a tap', (t) async {
    reduceMotionFor(t);
    var taps = 0;
    await t.pumpWidget(_wrap(GradientIconTile(icon: Icons.bolt_rounded, onTap: () => taps++)));
    expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
    await t.tap(find.byType(GradientIconTile));
    expect(taps, 1);
  });
}
