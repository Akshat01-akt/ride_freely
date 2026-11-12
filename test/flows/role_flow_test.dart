import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:ride_freely/app.dart';
import 'package:ride_freely/core/core.dart';
import 'package:ride_freely/features/auth/login_page.dart';
import 'package:ride_freely/features/customer/customer_home_shell.dart';
import 'package:ride_freely/features/driver/driver_home_shell.dart';
import 'package:ride_freely/features/role_select/role_select_page.dart';

import '../fakes.dart';

class _BrokenRoleStore extends MemoryRoleStore {
  @override
  Future<UserRole?> read() async => throw StateError('keystore unavailable');
}

Future<void> _pump(WidgetTester t, Fakes f) async {
  f.install();
  await t.pumpWidget(const RideFreelyApp());
  await t.pumpAndSettle();
}

Brightness _brightness(WidgetTester t, Type page) =>
    Theme.of(t.element(find.byType(page))).brightness;

void main() {
  testWidgets('first launch with no stored role shows the role choice', (t) async {
    await _pump(t, Fakes());
    expect(find.byType(RoleSelectPage), findsOneWidget);
    expect(find.text('I need a driver'), findsOneWidget);
    expect(find.text("I'm a driver"), findsOneWidget);
  });

  testWidgets('choosing driver opens the driver login and remembers the choice', (t) async {
    final f = Fakes();
    await _pump(t, f);
    await t.tap(find.byKey(const Key('role_driver')));
    await t.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.textContaining('Earn on your terms'), findsOneWidget);
    expect(await f.roleStore.read(), UserRole.driver);
  });

  testWidgets('choosing customer opens the customer login', (t) async {
    final f = Fakes();
    await _pump(t, f);
    await t.tap(find.byKey(const Key('role_customer')));
    await t.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.textContaining('Our driver'), findsOneWidget);
    expect(await f.roleStore.read(), UserRole.customer);
  });

  testWidgets('remembered driver with a valid session goes straight to the driver dashboard', (t) async {
    await _pump(
      t,
      Fakes(storedRole: UserRole.driver, driver: FakeAuthRepository(UserRole.driver, hasToken: true)),
    );
    expect(find.byType(DriverHomeShell), findsOneWidget);
    expect(find.byType(CustomerHomeShell), findsNothing);
  });

  testWidgets('remembered customer without a session goes to the customer login', (t) async {
    await _pump(t, Fakes(storedRole: UserRole.customer));
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.textContaining('Our driver'), findsOneWidget);
  });

  testWidgets('a failing role store does not strand the user on the splash screen', (t) async {
    final f = Fakes();
    f.install();
    Get.delete<RoleStore>(force: true);
    Get.put<RoleStore>(_BrokenRoleStore());
    await t.pumpWidget(const RideFreelyApp());
    await t.pumpAndSettle();
    expect(find.byType(RoleSelectPage), findsOneWidget);
  });

  testWidgets('switching account type returns to the role choice and forgets the role', (t) async {
    final f = Fakes(storedRole: UserRole.customer);
    await _pump(t, f);
    await t.tap(find.text('Switch account type'));
    await t.pumpAndSettle();
    expect(find.byType(RoleSelectPage), findsOneWidget);
    expect(await f.roleStore.read(), isNull);
  });

  testWidgets('customer interface is cream-led (light)', (t) async {
    await _pump(t, Fakes(storedRole: UserRole.customer));
    expect(_brightness(t, LoginPage), Brightness.light);
  });

  testWidgets('driver interface is dark-grey-led (dark)', (t) async {
    await _pump(t, Fakes(storedRole: UserRole.driver));
    expect(_brightness(t, LoginPage), Brightness.dark);
  });

  testWidgets('a customer session never shows driver-only tabs', (t) async {
    await _pump(
      t,
      Fakes(storedRole: UserRole.customer, customer: FakeAuthRepository(UserRole.customer, hasToken: true)),
    );
    expect(find.text('Book a driver'), findsOneWidget);
    expect(find.text('Requests'), findsNothing);
    expect(find.text('Earnings'), findsNothing);
  });
}
