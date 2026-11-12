import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:ride_freely/app.dart';
import 'package:ride_freely/core/core.dart';

import '../fakes.dart';

const _offline = ApiException('Cannot reach the server. Check your connection and try again.', address: 'http://10.0.2.2/api/v1');

Future<Fakes> _pump(WidgetTester t, {ApiException? loginError, UserRole role = UserRole.customer}) async {
  reduceMotionFor(t);
  final f = Fakes(
    storedRole: role,
    customer: FakeAuthRepository(UserRole.customer, loginException: loginError),
    driver: FakeAuthRepository(UserRole.driver, loginException: loginError),
  );
  f.install();
  await t.pumpWidget(const RideFreelyApp());
  await t.pumpAndSettle();
  return f;
}

Future<void> _failLogin(WidgetTester t) async {
  await t.enterText(find.byKey(const Key('phone')), '9876543210');
  await t.enterText(find.byKey(const Key('password')), 'password123');
  await t.tap(find.widgetWithText(AppButton, 'Log in'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('when the server cannot be reached the screen says which address was tried and offers to change it', (t) async {
    await _pump(t, loginError: _offline);
    await _failLogin(t);
    expect(find.textContaining('Cannot reach the server'), findsOneWidget);
    expect(find.textContaining('http://10.0.2.2/api/v1'), findsOneWidget);
    expect(find.text('Change server address'), findsOneWidget);
  });

  testWidgets('a wrong password is not a connection problem, so no server hint is shown', (t) async {
    await _pump(t, loginError: const ApiException('Invalid phone or password', statusCode: 401));
    await _failLogin(t);
    expect(find.text('Invalid phone or password'), findsOneWidget);
    expect(find.text('Change server address'), findsNothing);
  });

  testWidgets('entering a new address saves it and tells the user to try again', (t) async {
    final f = await _pump(t, loginError: _offline);
    await _failLogin(t);
    await t.tap(find.text('Change server address'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('server_address_field')), findsOneWidget);
    await t.enterText(find.byKey(const Key('server_address_field')), '192.168.29.218');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(f.serverConfig.url.value, 'http://192.168.29.218/api/v1');
    expect(find.textContaining('Server address saved'), findsOneWidget);
    expect(find.byKey(const Key('server_address_field')), findsNothing);
  });

  testWidgets('an invalid address is explained and the dialog stays open', (t) async {
    final f = await _pump(t, loginError: _offline);
    await _failLogin(t);
    await t.tap(find.text('Change server address'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('server_address_field')), 'ftp://nope');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.textContaining('Enter an address like'), findsOneWidget);
    expect(find.byKey(const Key('server_address_field')), findsOneWidget);
    expect(f.serverConfig.url.value, isNot(contains('ftp')));
  });

  testWidgets('the dialog shows the current address and can reset to the default', (t) async {
    final f = await _pump(t, loginError: _offline);
    await f.serverConfig.set('10.9.9.9');
    await _failLogin(t);
    await t.tap(find.text('Change server address'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'http://10.9.9.9/api/v1'), findsOneWidget);
    await t.tap(find.text('Use default'));
    await t.pumpAndSettle();
    expect(f.serverConfig.url.value, f.serverConfig.defaultUrl);
  });

  testWidgets('cancelling changes nothing', (t) async {
    final f = await _pump(t, loginError: _offline);
    final before = f.serverConfig.url.value;
    await _failLogin(t);
    await t.tap(find.text('Change server address'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(f.serverConfig.url.value, before);
  });

  testWidgets('the same help appears on the driver login and on registration', (t) async {
    await _pump(t, loginError: _offline, role: UserRole.driver);
    await _failLogin(t);
    expect(find.text('Change server address'), findsOneWidget);
  });

  testWidgets('registration shows the help too when it cannot connect', (t) async {
    reduceMotionFor(t);
    final f = Fakes(storedRole: UserRole.customer, customer: FakeAuthRepository(UserRole.customer, registerException: _offline));
    f.install();
    await t.pumpWidget(const RideFreelyApp());
    await t.pumpAndSettle();
    Get.toNamed('/customer/register');
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('name')), 'Asha Rao');
    await t.enterText(find.byKey(const Key('phone')), '9876543210');
    await t.enterText(find.byKey(const Key('password')), 'password123');
    await t.tap(find.widgetWithText(AppButton, 'Create account'));
    await t.pumpAndSettle();
    expect(find.text('Change server address'), findsOneWidget);
  });

  testWidgets('the help fits a small phone', (t) async {
    reduceMotionFor(t, size: const Size(320, 568));
    final f = Fakes(storedRole: UserRole.customer, customer: FakeAuthRepository(UserRole.customer, loginException: _offline));
    f.install();
    await t.pumpWidget(const RideFreelyApp());
    await t.pumpAndSettle();
    await _failLogin(t);
    await t.tap(find.text('Change server address'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
