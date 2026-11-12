import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:ride_freely/app.dart';
import 'package:ride_freely/core/core.dart';
import 'package:ride_freely/features/onboarding/onboarding_page.dart';
import 'package:ride_freely/features/role_select/role_select_page.dart';

import '../fakes.dart';

Future<void> _pump(WidgetTester t, {bool done = false, UserRole? role, Size size = const Size(390, 844)}) async {
  reduceMotionFor(t, size: size);
  Fakes(onboardingDone: done, storedRole: role).install();
  await t.pumpWidget(const RideFreelyApp());
  await t.pumpAndSettle();
}

void main() {
  testWidgets('first launch shows the intro slides before role selection', (t) async {
    await _pump(t);
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.textContaining('Professional drivers'), findsOneWidget);
  });

  testWidgets('Next moves through the slides and the last one says Get started', (t) async {
    await _pump(t);
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(find.textContaining('Book by the hour'), findsOneWidget);
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(find.text('Get started'), findsOneWidget);
    await t.tap(find.text('Get started'));
    await t.pumpAndSettle();
    expect(find.byType(RoleSelectPage), findsOneWidget);
    expect(await Get.find<OnboardingStore>().isDone(), isTrue);
  });

  testWidgets('Skip goes straight to role selection and is remembered', (t) async {
    await _pump(t);
    await t.tap(find.text('Skip'));
    await t.pumpAndSettle();
    expect(find.byType(RoleSelectPage), findsOneWidget);
    expect(await Get.find<OnboardingStore>().isDone(), isTrue);
  });

  testWidgets('a returning user never sees the intro again', (t) async {
    await _pump(t, done: true);
    expect(find.byType(OnboardingPage), findsNothing);
    expect(find.byType(RoleSelectPage), findsOneWidget);
  });

  testWidgets('a user with a remembered role skips the intro even if it was never marked done', (t) async {
    await _pump(t, role: UserRole.customer);
    expect(find.byType(OnboardingPage), findsNothing);
  });

  testWidgets('intro fits a small phone', (t) async {
    await _pump(t, size: const Size(320, 568));
    expect(t.takeException(), isNull);
  });
}
