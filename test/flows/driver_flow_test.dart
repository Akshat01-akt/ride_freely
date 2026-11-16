import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:ride_freely/app.dart';
import 'package:ride_freely/core/core.dart';
import 'package:ride_freely/features/auth/login_page.dart';
import 'package:ride_freely/features/driver/application_page.dart';
import 'package:ride_freely/features/driver/data/driver_api.dart';
import 'package:ride_freely/features/driver/driver_home_shell.dart';
import 'package:ride_freely/features/driver/driver_register_page.dart';
import 'package:ride_freely/routes.dart';

import '../fakes.dart';

Future<void> _pumpApp(WidgetTester t, FakeAuthRepository repo) async {
  reduceMotionFor(t);
  Fakes(
    storedRole: UserRole.driver,
    driver: repo,
  ).install();
  await t.pumpWidget(const RideFreelyApp());
  await t.pumpAndSettle();
}

Future<void> _openRegister(WidgetTester t) async {
  Get.toNamed(Routes.register(UserRole.driver));
  await t.pumpAndSettle();
  expect(find.byType(DriverRegisterPage), findsOneWidget);
}

Future<void> _fillCommon(WidgetTester t) async {
  await t.enterText(find.byKey(const Key('name')), 'Ravi Kumar');
  await t.enterText(find.byKey(const Key('identifier')), '9876500000');
  await t.enterText(find.byKey(const Key('password')), 'password123');
}

void main() {
  testWidgets('splash without a stored token goes to login', (t) async {
    await _pumpApp(t, FakeAuthRepository(UserRole.driver));
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('successful login shows the dashboard', (t) async {
    final repo = FakeAuthRepository(UserRole.driver);
    await _pumpApp(t, repo);
    await t.enterText(find.byKey(const Key('identifier')), '9876500000');
    await t.enterText(find.byKey(const Key('password')), 'password123');
    await t.tap(find.widgetWithText(AppButton, 'Log in'));
    await t.pumpAndSettle();
    expect(repo.loginCalls, 1);
    expect(find.byType(DriverHomeShell), findsOneWidget);
    expect(find.textContaining('Ravi'), findsWidgets);
  });

  testWidgets('failed login shows the server message', (t) async {
    await _pumpApp(t, FakeAuthRepository(UserRole.driver, loginError: 'Invalid phone or password'));
    await t.enterText(find.byKey(const Key('identifier')), '9876500000');
    await t.enterText(find.byKey(const Key('password')), 'password123');
    await t.tap(find.widgetWithText(AppButton, 'Log in'));
    await t.pumpAndSettle();
    expect(find.text('Invalid phone or password'), findsOneWidget);
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('driver registration asks only for name, email or mobile, and password', (t) async {
    final repo = FakeAuthRepository(UserRole.driver, verification: 'NOT_SUBMITTED');
    await _pumpApp(t, repo);
    await _openRegister(t);
    expect(find.byKey(const Key('licence')), findsNothing);
    expect(find.byKey(const Key('hourly_rate')), findsNothing);
    await _fillCommon(t);
    await t.ensureVisible(find.widgetWithText(AppButton, 'Create account'));
    await t.tap(find.widgetWithText(AppButton, 'Create account'));
    await t.pumpAndSettle();
    expect(repo.registerCalls, 1);
    expect(repo.lastRegister, {'full_name': 'Ravi Kumar', 'phone': '9876500000', 'password': 'password123'});
    expect(find.byType(ApplicationPage), findsOneWidget);
  });

  testWidgets('registering with an email sends the email', (t) async {
    final repo = FakeAuthRepository(UserRole.driver, verification: 'NOT_SUBMITTED');
    await _pumpApp(t, repo);
    await _openRegister(t);
    await t.enterText(find.byKey(const Key('name')), 'Ravi Kumar');
    await t.enterText(find.byKey(const Key('identifier')), 'ravi@example.com');
    await t.enterText(find.byKey(const Key('password')), 'password123');
    await t.ensureVisible(find.widgetWithText(AppButton, 'Create account'));
    await t.tap(find.widgetWithText(AppButton, 'Create account'));
    await t.pumpAndSettle();
    expect(repo.lastRegister, {'full_name': 'Ravi Kumar', 'email': 'ravi@example.com', 'password': 'password123'});
  });

  testWidgets('a driver who has not applied sees the server form, not the dashboard', (t) async {
    final f = Fakes(storedRole: UserRole.driver, driver: FakeAuthRepository(UserRole.driver, hasToken: true, verification: 'NOT_SUBMITTED'));
    f.driverApi.form = FormSpec.fromJson({
      'version': 1,
      'fields': [
        {'key': 'licence_number', 'label': 'Driving licence number', 'field_type': 'text', 'required': true},
        {'key': 'LICENCE', 'label': 'Driving licence', 'field_type': 'document', 'required': true},
      ],
    });
    reduceMotionFor(t);
    f.install();
    await t.pumpWidget(const RideFreelyApp());
    await t.pumpAndSettle();
    expect(find.byType(DriverHomeShell), findsOneWidget);
    expect(find.byType(ApplicationPage), findsOneWidget);
    expect(find.text('Your driver application'), findsOneWidget);
    expect(find.text('Verification pending'), findsNothing);
    await t.tap(find.text('Submit application'));
    await t.pump();
    expect(f.driverApi.submitted, isEmpty); // required answer missing
    await t.enterText(find.byKey(const Key('field_licence_number')), 'DL-0420110012345');
    await t.tap(find.text('Submit application'));
    await t.pumpAndSettle();
    expect(f.driverApi.submitted, [
      {'licence_number': 'DL-0420110012345'}
    ]);
  });

  testWidgets('a field error from the server is shown on submit', (t) async {
    final f = Fakes(storedRole: UserRole.driver, driver: FakeAuthRepository(UserRole.driver, hasToken: true, verification: 'NOT_SUBMITTED'));
    f.driverApi
      ..form = FormSpec.fromJson({
        'version': 1,
        'fields': [
          {'key': 'licence_number', 'label': 'Driving licence number', 'field_type': 'text', 'required': true},
        ],
      })
      ..submitError = const ApiException('x', statusCode: 422, fieldErrors: {'licence_number': 'This is not valid'});
    reduceMotionFor(t);
    f.install();
    await t.pumpWidget(const RideFreelyApp());
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('field_licence_number')), 'DL-1');
    await t.tap(find.text('Submit application'));
    await t.pumpAndSettle();
    expect(find.text('This is not valid'), findsOneWidget);
  });

  testWidgets('a driver sent back for changes sees the reviewer note and can only edit the flagged item', (t) async {
    final f = Fakes(storedRole: UserRole.driver, driver: FakeAuthRepository(UserRole.driver, hasToken: true, verification: 'REJECTED'));
    f.driverApi
      ..form = FormSpec.fromJson({
        'version': 1,
        'fields': [
          {'key': 'licence_number', 'label': 'Driving licence number', 'field_type': 'text', 'required': true},
          {'key': 'hourly_rate', 'label': 'Hourly rate', 'field_type': 'number', 'required': true},
        ],
      })
      ..applicationData = DriverApplication.fromJson({
        'status': 'REJECTED',
        'answers': [
          {'key': 'licence_number', 'value': 'DL-1', 'status': 'APPROVED', 'review_note': null},
          {'key': 'hourly_rate', 'value': '999', 'status': 'REJECTED', 'review_note': 'Too high'},
        ],
        'documents': [],
        'needs_update': [],
      });
    reduceMotionFor(t);
    f.install();
    await t.pumpWidget(const RideFreelyApp());
    await t.pumpAndSettle();
    expect(find.text('Needs changes'), findsOneWidget);
    expect(find.text('Needs changes: Too high'), findsOneWidget);
    expect(find.byKey(const Key('field_licence_number')), findsNothing);
    await t.enterText(find.byKey(const Key('field_hourly_rate')), '150');
    await t.tap(find.text('Send for review again'));
    await t.pumpAndSettle();
    expect(f.driverApi.submitted, [
      {'hourly_rate': '150'}
    ]);
  });

  testWidgets('an approved driver with new required questions sees the update card and stays bookable', (t) async {
    await _pumpApp(t, FakeAuthRepository(UserRole.driver, hasToken: true, verification: 'APPROVED', needsUpdate: ['badge_no']));
    expect(find.text('Please update your details'), findsOneWidget);
    expect(t.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
    await t.tap(find.text('Later'));
    await t.pumpAndSettle();
    expect(find.text('Please update your details'), findsNothing);
  });

  testWidgets('an approved driver with nothing new sees no update card', (t) async {
    await _pumpApp(t, FakeAuthRepository(UserRole.driver, hasToken: true, verification: 'APPROVED'));
    expect(find.text('Please update your details'), findsNothing);
  });

  testWidgets('pending driver sees the verification banner and cannot go online', (t) async {
    await _pumpApp(t, FakeAuthRepository(UserRole.driver, hasToken: true, verification: 'PENDING'));
    expect(find.text('Verification pending'), findsOneWidget);
    final sw = t.widget<Switch>(find.byType(Switch));
    expect(sw.onChanged, isNull);
  });

  testWidgets('approved driver can toggle online', (t) async {
    await _pumpApp(t, FakeAuthRepository(UserRole.driver, hasToken: true, verification: 'APPROVED'));
    expect(find.text('Verification pending'), findsNothing);
    expect(find.text('You are offline'), findsOneWidget);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(find.text('You are online'), findsOneWidget);
    Get.deleteAll(force: true); // closes controllers, stopping the location timer, before the test ends
  });

  testWidgets('log out from profile returns to login', (t) async {
    await _pumpApp(t, FakeAuthRepository(UserRole.driver, hasToken: true));
    await t.tap(find.text('Profile'));
    await t.pumpAndSettle();
    await t.tap(find.text('Log out'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Log out'));
    await t.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('choosing Stay on the logout prompt keeps the session', (t) async {
    await _pumpApp(t, FakeAuthRepository(UserRole.driver, hasToken: true));
    await t.tap(find.text('Profile'));
    await t.pumpAndSettle();
    await t.tap(find.text('Log out'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Stay'));
    await t.pumpAndSettle();
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets('going online calls the server and starts sharing location', (t) async {
    final f = Fakes(storedRole: UserRole.driver, driver: FakeAuthRepository(UserRole.driver, hasToken: true, verification: 'APPROVED'));
    reduceMotionFor(t);
    f.install();
    await t.pumpWidget(const RideFreelyApp());
    await t.pumpAndSettle();
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(f.driverApi.calls, ['setAvailability:true', 'sendLocation']);
    expect(find.text('You are online'), findsOneWidget);
    Get.deleteAll(force: true); // closes controllers, stopping the location timer, before the test ends
  });

  testWidgets('a server rejection puts the switch back to offline and explains why', (t) async {
    final api = FakeDriverApi()..availabilityError = const ApiException('Your documents must be approved before you can go online', statusCode: 403);
    final f = Fakes(storedRole: UserRole.driver, driver: FakeAuthRepository(UserRole.driver, hasToken: true, verification: 'APPROVED'), driverApi: api);
    reduceMotionFor(t);
    f.install();
    await t.pumpWidget(const RideFreelyApp());
    await t.pumpAndSettle();
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(find.text('You are offline'), findsOneWidget);
    expect(find.textContaining('documents must be approved'), findsOneWidget);
  });

  testWidgets('denied location permission is explained and the driver stays offline', (t) async {
    final loc = FakeLocationService(error: const LocationException(LocationProblem.denied));
    final f = Fakes(storedRole: UserRole.driver, driver: FakeAuthRepository(UserRole.driver, hasToken: true, verification: 'APPROVED'), location: loc);
    reduceMotionFor(t);
    f.install();
    await t.pumpWidget(const RideFreelyApp());
    await t.pumpAndSettle();
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(find.text('You are offline'), findsOneWidget);
    expect(find.textContaining('Location permission is needed'), findsOneWidget);
    expect(f.driverApi.calls, isEmpty);
  });

  testWidgets('logging out while online tells the server the driver is offline', (t) async {
    final f = Fakes(storedRole: UserRole.driver, driver: FakeAuthRepository(UserRole.driver, hasToken: true, verification: 'APPROVED'));
    reduceMotionFor(t);
    f.install();
    await t.pumpWidget(const RideFreelyApp());
    await t.pumpAndSettle();
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    await t.tap(find.text('Profile'));
    await t.pumpAndSettle();
    await t.tap(find.text('Log out'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Log out'));
    await t.pumpAndSettle();
    expect(f.driverApi.calls.last, 'setAvailability:false');
  });
}
