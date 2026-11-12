import 'package:customer_app/app.dart';
import 'package:customer_app/features/auth/login_page.dart';
import 'package:customer_app/features/auth/register_page.dart';
import 'package:customer_app/features/home/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'fakes.dart';

Future<void> _pumpApp(WidgetTester t, FakeAuthRepository repo) async {
  installController(repo);
  await t.pumpWidget(const CustomerApp());
  await t.pumpAndSettle();
}

void main() {
  testWidgets('splash without a stored token goes to login', (t) async {
    await _pumpApp(t, FakeAuthRepository());
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('splash with a valid stored session goes straight to home', (t) async {
    await _pumpApp(t, FakeAuthRepository(hasToken: true));
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.textContaining('Asha'), findsWidgets);
  });

  testWidgets('login page shows validation errors on empty submit', (t) async {
    final repo = FakeAuthRepository();
    await _pumpApp(t, repo);
    await t.tap(find.widgetWithText(FilledButton, 'Log in'));
    await t.pumpAndSettle();
    expect(find.text('Enter your phone number'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(repo.loginCalls, 0);
  });

  testWidgets('successful login navigates to the home shell', (t) async {
    final repo = FakeAuthRepository();
    await _pumpApp(t, repo);
    await t.enterText(find.byKey(const Key('phone')), '9876543210');
    await t.enterText(find.byKey(const Key('password')), 'password123');
    await t.tap(find.widgetWithText(FilledButton, 'Log in'));
    await t.pumpAndSettle();
    expect(repo.loginCalls, 1);
    expect(find.byType(HomeShell), findsOneWidget);
  });

  testWidgets('failed login shows the server message and stays on login', (t) async {
    await _pumpApp(t, FakeAuthRepository(loginError: 'Invalid phone or password'));
    await t.enterText(find.byKey(const Key('phone')), '9876543210');
    await t.enterText(find.byKey(const Key('password')), 'password123');
    await t.tap(find.widgetWithText(FilledButton, 'Log in'));
    await t.pumpAndSettle();
    expect(find.text('Invalid phone or password'), findsOneWidget);
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('register page rejects a short password', (t) async {
    final repo = FakeAuthRepository();
    await _pumpApp(t, repo);
    Get.toNamed('/register');
    await t.pumpAndSettle();
    expect(find.byType(RegisterPage), findsOneWidget);
    await t.enterText(find.byKey(const Key('name')), 'Asha Rao');
    await t.enterText(find.byKey(const Key('phone')), '9876543210');
    await t.enterText(find.byKey(const Key('password')), 'short');
    await t.tap(find.widgetWithText(FilledButton, 'Create account'));
    await t.pumpAndSettle();
    expect(find.text('Use at least 8 characters'), findsOneWidget);
    expect(repo.registerCalls, 0);
  });

  testWidgets('register sends optional email only when filled', (t) async {
    final repo = FakeAuthRepository();
    await _pumpApp(t, repo);
    Get.toNamed('/register');
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('name')), 'Asha Rao');
    await t.enterText(find.byKey(const Key('phone')), '9876543210');
    await t.enterText(find.byKey(const Key('password')), 'password123');
    await t.tap(find.widgetWithText(FilledButton, 'Create account'));
    await t.pumpAndSettle();
    expect(repo.registerCalls, 1);
    expect(repo.lastRegister!.containsKey('email'), isFalse);
    expect(find.byType(HomeShell), findsOneWidget);
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
