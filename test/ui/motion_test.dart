import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:ride_freely/app.dart';
import 'package:ride_freely/core/core.dart';
import 'package:ride_freely/features/auth/auth_scaffold.dart';

import '../fakes.dart';

double _slideDx(WidgetTester t, Finder inside) =>
    t.widget<SlideTransition>(find.ancestor(of: inside, matching: find.byType(SlideTransition)).first).position.value.dx;

Widget _twoPageApp() => GetMaterialApp(
      customTransition: AppPageTransition(),
      transitionDuration: AppMotion.page,
      initialRoute: '/',
      getPages: [
        GetPage(name: '/', page: () => Scaffold(body: Center(child: ElevatedButton(onPressed: () => Get.toNamed('/second'), child: const Text('go'))))),
        GetPage(name: '/second', page: () => const Scaffold(body: Text('second page'))),
      ],
    );

Widget _surface({VoidCallback? onTap}) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: HoverSurface(key: const Key('s'), onTap: onTap, child: const SizedBox(width: 120, height: 60, child: Text('card'))))),
    );

BoxDecoration _decoration(WidgetTester t) =>
    t.widget<AnimatedContainer>(find.descendant(of: find.byKey(const Key('s')), matching: find.byType(AnimatedContainer)).first).decoration! as BoxDecoration;

Future<TestGesture> _hover(WidgetTester t, Finder f) async {
  final g = await t.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: Offset.zero);
  addTearDown(g.removePointer);
  await g.moveTo(t.getCenter(f));
  await t.pumpAndSettle();
  return g;
}

void main() {
  testWidgets('a pushed page fades and slides in, then settles fully visible', (t) async {
    await t.pumpWidget(_twoPageApp());
    await t.tap(find.text('go'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final fade = t.widget<FadeTransition>(find.ancestor(of: find.text('second page'), matching: find.byType(FadeTransition)).first);
    expect(fade.opacity.value, inInclusiveRange(0.01, 0.99));
    expect(_slideDx(t, find.text('second page')), greaterThan(0));
    await t.pumpAndSettle();
    expect(t.widget<FadeTransition>(find.ancestor(of: find.text('second page'), matching: find.byType(FadeTransition)).first).opacity.value, 1);
    expect(_slideDx(t, find.text('second page')), 0);
  });

  testWidgets('the page underneath eases back while a new one arrives', (t) async {
    await t.pumpWidget(_twoPageApp());
    await t.tap(find.text('go'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 150));
    final scale = t.widget<ScaleTransition>(find.ancestor(of: find.text('go'), matching: find.byType(ScaleTransition)).first);
    expect(scale.scale.value, lessThan(1));
    await t.pumpAndSettle();
  });

  testWidgets('with reduced motion pages appear without sliding or fading', (t) async {
    reduceMotionFor(t);
    await t.pumpWidget(_twoPageApp());
    await t.tap(find.text('go'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('second page'), findsOneWidget);
    expect(find.ancestor(of: find.text('second page'), matching: find.byType(SlideTransition)), findsNothing);
  });

  testWidgets('tabs slide in from the right when moving forward and from the left when moving back', (t) async {
    final index = ValueNotifier(0);
    await t.pumpWidget(MaterialApp(home: ValueListenableBuilder<int>(valueListenable: index, builder: (_, i, _) => AnimatedTabSwitcher(index: i, builder: (i) => Text('tab$i')))));
    index.value = 2;
    await t.pump();
    await t.pump(const Duration(milliseconds: 80));
    expect(_slideDx(t, find.text('tab2')), greaterThan(0));
    await t.pumpAndSettle();
    expect(find.text('tab0'), findsNothing);
    index.value = 1;
    await t.pump();
    await t.pump(const Duration(milliseconds: 80));
    expect(_slideDx(t, find.text('tab1')), lessThan(0));
    await t.pumpAndSettle();
    expect(find.text('tab1'), findsOneWidget);
  });

  testWidgets('tab switching with reduced motion is instant', (t) async {
    reduceMotionFor(t);
    final index = ValueNotifier(0);
    await t.pumpWidget(MaterialApp(home: ValueListenableBuilder<int>(valueListenable: index, builder: (_, i, _) => AnimatedTabSwitcher(index: i, builder: (i) => Text('tab$i')))));
    index.value = 1;
    await t.pump();
    expect(find.text('tab1'), findsOneWidget);
    expect(find.text('tab0'), findsNothing);
  });

  testWidgets('hovering a surface lifts it: stronger shadow and a highlighted border', (t) async {
    await t.pumpWidget(_surface(onTap: () {}));
    final before = _decoration(t);
    await _hover(t, find.text('card'));
    final after = _decoration(t);
    expect(after.boxShadow!.first.blurRadius, greaterThan(before.boxShadow!.first.blurRadius));
    expect((after.border! as Border).top.color.a, greaterThan((before.border! as Border).top.color.a));
  });

  testWidgets('a surface returns to rest when the mouse leaves, and tapping still works', (t) async {
    var taps = 0;
    await t.pumpWidget(_surface(onTap: () => taps++));
    final rest = _decoration(t).boxShadow!.first.blurRadius;
    final g = await _hover(t, find.text('card'));
    await g.moveTo(const Offset(5, 5));
    await t.pumpAndSettle();
    expect(_decoration(t).boxShadow!.first.blurRadius, rest);
    await t.tap(find.text('card'));
    expect(taps, 1);
  });

  testWidgets('a surface with no tap handler still reacts to hover (for static cards)', (t) async {
    await t.pumpWidget(_surface());
    final before = _decoration(t).boxShadow!.first.blurRadius;
    await _hover(t, find.text('card'));
    expect(_decoration(t).boxShadow!.first.blurRadius, greaterThan(before));
  });

  testWidgets('a link grows an underline on hover and fires on tap', (t) async {
    var taps = 0;
    await t.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: Center(child: HoverLink(label: 'Create an account', onTap: () => taps++)))));
    double underline() => t.widget<FractionallySizedBox>(find.byKey(const Key('hover_link_underline'))).widthFactor!;
    expect(underline(), 0);
    await _hover(t, find.text('Create an account'));
    expect(underline(), 1);
    await t.tap(find.text('Create an account'));
    expect(taps, 1);
  });

  testWidgets('a new error message shakes once, then rests', (t) async {
    final msg = ValueNotifier<String?>(null);
    await t.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: ValueListenableBuilder<String?>(valueListenable: msg, builder: (_, m, _) => FormError(m)))));
    msg.value = 'Invalid phone or password';
    await t.pump();
    await t.pump(const Duration(milliseconds: 90));
    double dx() => t.widget<Transform>(find.descendant(of: find.byType(FormError), matching: find.byKey(const Key('shake'))).first).transform.getTranslation().x;
    expect(dx().abs(), greaterThan(0));
    await t.pumpAndSettle();
    expect(dx(), 0);
    expect(find.text('Invalid phone or password'), findsOneWidget);
  });

  testWidgets('with reduced motion an error appears without shaking', (t) async {
    reduceMotionFor(t);
    await t.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: FormError('Nope'))));
    expect(find.byKey(const Key('shake')), findsNothing);
    expect(find.text('Nope'), findsOneWidget);
  });

  testWidgets('moving from login to register in the real app slides the new page in', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Fakes(storedRole: UserRole.customer).install();
    await t.pumpWidget(const RideFreelyApp());
    await t.pump(const Duration(seconds: 3)); // splash hold, then the route to login
    await t.pump(const Duration(milliseconds: 700));
    await t.tap(find.text('Create an account'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    expect(_slideDx(t, find.text('Create your account')), greaterThan(0));
    await t.pump(const Duration(milliseconds: 800));
    expect(_slideDx(t, find.text('Create your account')), 0);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the login form sits in a card that lifts on hover', (t) async {
    reduceMotionFor(t);
    Fakes(storedRole: UserRole.customer).install();
    await t.pumpWidget(const RideFreelyApp());
    await t.pumpAndSettle();
    expect(find.byKey(const Key('auth_card')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('auth_card')), matching: find.byKey(const Key('identifier'))), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('auth_card')), matching: find.text('Log in')), findsOneWidget);
    final decoration = t.widget<AnimatedContainer>(find.descendant(of: find.byKey(const Key('auth_card')), matching: find.byType(AnimatedContainer)).first).decoration! as BoxDecoration;
    final rest = decoration.boxShadow!.first.blurRadius;
    final g = await t.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: Offset.zero);
    addTearDown(g.removePointer);
    await g.moveTo(t.getCenter(find.byKey(const Key('auth_card'))));
    await t.pumpAndSettle();
    final lifted = t.widget<AnimatedContainer>(find.descendant(of: find.byKey(const Key('auth_card')), matching: find.byType(AnimatedContainer)).first).decoration! as BoxDecoration;
    expect(lifted.boxShadow!.first.blurRadius, greaterThan(rest));
  });
}
