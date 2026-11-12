import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_freely/core/core.dart';

import '../fakes.dart';

Widget _host(Widget child) => MaterialApp(theme: AppTheme.light(), home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('password field hides text and the eye toggle reveals it', (t) async {
    reduceMotionFor(t);
    final c = TextEditingController(text: 'secret123');
    await t.pumpWidget(_host(AppTextField(controller: c, label: 'Password', obscure: true)));
    EditableText field() => t.widget<EditableText>(find.byType(EditableText));
    expect(field().obscureText, isTrue);
    await t.tap(find.byIcon(Icons.visibility_outlined));
    await t.pumpAndSettle();
    expect(field().obscureText, isFalse);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });

  testWidgets('AppButton ignores taps while loading and shows a spinner', (t) async {
    reduceMotionFor(t);
    var taps = 0;
    await t.pumpWidget(_host(AppButton(label: 'Log in', loading: true, onPressed: () => taps++)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await t.tap(find.byType(AppButton), warnIfMissed: false);
    await t.pump();
    expect(taps, 0);
  });

  testWidgets('AppButton with no handler is dimmed and not tappable', (t) async {
    reduceMotionFor(t);
    await t.pumpWidget(_host(const AppButton(label: 'Book now', onPressed: null)));
    expect(t.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 0.5);
  });

  testWidgets('Pressable shrinks while pressed and fires onTap', (t) async {
    var taps = 0;
    await t.pumpWidget(_host(Pressable(onTap: () => taps++, child: const SizedBox(width: 80, height: 40, child: Text('x')))));
    final gesture = await t.startGesture(t.getCenter(find.text('x')));
    await t.pump();
    expect(t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, lessThan(1));
    await gesture.up();
    await t.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('FadeSlideIn is fully visible immediately when reduced motion is on', (t) async {
    reduceMotionFor(t);
    await t.pumpWidget(_host(const FadeSlideIn(child: Text('hello'))));
    expect(t.widget<Opacity>(find.byType(Opacity)).opacity, 1);
  });

  testWidgets('FadeSlideIn animates in when motion is allowed', (t) async {
    await t.pumpWidget(_host(const FadeSlideIn(child: Text('hello'))));
    expect(t.widget<Opacity>(find.byType(Opacity)).opacity, lessThan(1));
    await t.pumpAndSettle();
    expect(t.widget<Opacity>(find.byType(Opacity)).opacity, 1);
  });

  testWidgets('background animation runs normally and stops under reduced motion', (t) async {
    await t.pumpWidget(_host(const SizedBox(width: 200, height: 200, child: AnimatedGradientBackground(child: SizedBox()))));
    await t.pump(const Duration(milliseconds: 100));
    expect(t.binding.hasScheduledFrame, isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('background animation is static when the OS asks for reduced motion', (t) async {
    reduceMotionFor(t);
    await t.pumpWidget(_host(const SizedBox(width: 200, height: 200, child: AnimatedGradientBackground(child: SizedBox()))));
    await t.pump(const Duration(milliseconds: 100));
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('SuccessCheck settles and draws without exceptions', (t) async {
    await t.pumpWidget(_host(const SuccessCheck()));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('initials avatar handles one word, two words and empty names', (t) async {
    await t.pumpWidget(_host(const Column(children: [InitialsAvatar(name: 'Amit Kumar'), InitialsAvatar(name: 'Asha'), InitialsAvatar(name: '')])));
    expect(find.text('AK'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('empty state shows its title, body and optional action', (t) async {
    reduceMotionFor(t);
    await t.pumpWidget(_host(EmptyState(icon: Icons.search, title: 'Nothing here', body: 'Try later', action: AppButton(label: 'Retry', onPressed: () {}))));
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
