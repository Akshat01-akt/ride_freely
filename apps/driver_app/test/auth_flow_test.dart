import 'package:driver_app/app.dart';
import 'package:driver_app/features/auth/login_page.dart';
import 'package:driver_app/features/auth/register_page.dart';
import 'package:driver_app/features/home/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'fakes.dart';

Future<void> _pumpApp(WidgetTester t, FakeAuthRepository repo) async {
  installController(repo);
  await t.pumpWidget(const DriverApp());
  await t.pumpAndSettle();
}

Future<void> _openRegister(WidgetTester t) async {
  Get.toNamed('/register');
  await t.pumpAndSettle();
  expect(find.byType(RegisterPage), findsOneWidget);
}

Future<void> _fillCommon(WidgetTester t) async {
  await t.enterText(find.byKey(const Key('name')), 'Ravi Kumar');
  await t.enterText(find.byKey(const Key('phone')), '9876500000');
  await t.enterText(find.byKey(const Key('password')), 'password123');
}

void main() {
  testWidgets('splash without a stored token goes to login', (t) async {
    await _pumpApp(t, FakeAuthRepository());
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('successful login shows the dashboard', (t) async {
    final repo = FakeAuthRepository();
    await _pumpApp(t, repo);
    await t.enterText(find.byKey(const Key('phone')), '9876500000');
    await t.enterText(find.byKey(const Key('password')), 'password123');
    await t.tap(find.widgetWithText(FilledButton, 'Log in'));
    await t.pumpAndSettle();
    expect(repo.loginCalls, 1);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.textContaining('Ravi'), findsWidgets);
  });

  testWidgets('failed login shows the server message', (t) async {
    await _pumpApp(t, FakeAuthRepository(loginError: 'Invalid phone or password'));
    await t.enterText(find.byKey(const Key('phone')), '9876500000');
    await t.enterText(find.byKey(const Key('password')), 'password123');
    await t.tap(find.widgetWithText(FilledButton, 'Log in'));
    await t.pumpAndSettle();
    expect(find.text('Invalid phone or password'), findsOneWidget);
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('driver register requires licence and a positive hourly rate', (t) async {
    final repo = FakeAuthRepository();
    await _pumpApp(t, repo);
    await _openRegister(t);
    await _fillCommon(t);
    await t.enterText(find.byKey(const Key('hourly_rate')), '0');
    await t.ensureVisible(find.widgetWithText(FilledButton, 'Create account'));
    await t.tap(find.widgetWithText(FilledButton, 'Create account'));
    await t.pumpAndSettle();
    expect(find.text('Enter your licence number'), findsOneWidget);
    expect(find.text('Enter a rate above 0'), findsOneWidget);
    expect(repo.registerCalls, 0);
  });

  testWidgets('valid driver registration sends driver fields and opens the dashboard', (t) async {
    final repo = FakeAuthRepository();
    await _pumpApp(t, repo);
    await _openRegister(t);
    await _fillCommon(t);
    await t.enterText(find.byKey(const Key('licence')), 'DL-0420110012345');
    await t.enterText(find.byKey(const Key('experience')), '6');
    await t.enterText(find.byKey(const Key('hourly_rate')), '180');
    await t.ensureVisible(find.widgetWithText(FilledButton, 'Create account'));
    await t.tap(find.widgetWithText(FilledButton, 'Create account'));
    await t.pumpAndSettle();
    expect(repo.registerCalls, 1);
    expect(repo.lastRegister!['licence_number'], 'DL-0420110012345');
    expect(repo.lastRegister!['experience_years'], 6);
    expect(repo.lastRegister!['hourly_rate'], '180');
    expect(find.byType(HomeShell), findsOneWidget);
  });

  testWidgets('pending driver sees the verification banner and cannot go online', (t) async {
    await _pumpApp(t, FakeAuthRepository(hasToken: true, verification: 'PENDING'));
    expect(find.text('Verification pending'), findsOneWidget);
    final sw = t.widget<Switch>(find.byType(Switch));
    expect(sw.onChanged, isNull);
  });

  testWidgets('approved driver can toggle online', (t) async {
    await _pumpApp(t, FakeAuthRepository(hasToken: true, verification: 'APPROVED'));
    expect(find.text('Verification pending'), findsNothing);
    expect(find.text('You are offline'), findsOneWidget);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(find.text('You are online'), findsOneWidget);
  });

  testWidgets('log out from profile returns to login', (t) async {
    await _pumpApp(t, FakeAuthRepository(hasToken: true));
    await t.tap(find.text('Profile'));
    await t.pumpAndSettle();
    await t.tap(find.text('Log out'));
    await t.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  });
}
