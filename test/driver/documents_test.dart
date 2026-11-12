import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:ride_freely/app.dart';
import 'package:ride_freely/core/core.dart';
import 'package:ride_freely/features/driver/data/driver_api.dart';
import 'package:ride_freely/features/driver/documents_controller.dart';
import 'package:ride_freely/features/driver/documents_page.dart';
import 'package:ride_freely/features/role_theme.dart';

import '../fakes.dart';

Future<Fakes> _open(WidgetTester t, {List<DriverDocument> docs = const [], FakePicker? picker, FakeDriverApi? api, String verification = 'PENDING'}) async {
  reduceMotionFor(t);
  final f = Fakes(
    storedRole: UserRole.driver,
    driver: FakeAuthRepository(UserRole.driver, hasToken: true, verification: verification),
    driverApi: (api ?? FakeDriverApi())..docs = docs,
    picker: picker,
  );
  f.install();
  await t.pumpWidget(const RideFreelyApp());
  await t.pumpAndSettle();
  return f;
}

Future<void> _openDocuments(WidgetTester t) async {
  await t.tap(find.text('Upload documents'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('dashboard banner leads to the documents screen listing all three documents', (t) async {
    await _open(t);
    await _openDocuments(t);
    expect(find.byType(DocumentsPage), findsOneWidget);
    expect(find.text('Driving licence'), findsOneWidget);
    expect(find.text('ID proof'), findsOneWidget);
    expect(find.text('Profile photo'), findsOneWidget);
    expect(find.text('Not uploaded'), findsNWidgets(3));
    expect(find.text('0 of 2 required documents uploaded'), findsOneWidget);
  });

  testWidgets('shows each document status and the reviewer note for a rejected one', (t) async {
    await _open(t, docs: const [
      DriverDocument(type: 'LICENCE', status: DocumentStatus.approved),
      DriverDocument(type: 'ID_PROOF', status: DocumentStatus.rejected, note: 'Photo is blurry'),
      DriverDocument(type: 'PHOTO', status: DocumentStatus.pending),
    ]);
    await _openDocuments(t);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Photo is blurry'), findsOneWidget);
    expect(find.text('Pending review'), findsOneWidget);
    expect(find.text('2 of 2 required documents uploaded'), findsOneWidget);
    expect(find.text('Upload again'), findsOneWidget);
  });

  testWidgets('picking a file uploads it under the right type and refreshes the status', (t) async {
    final api = FakeDriverApi();
    final f = await _open(t, api: api);
    await _openDocuments(t);
    await t.tap(find.widgetWithText(AppButton, 'Upload').first);
    await t.pumpAndSettle();
    expect(f.picker.calls, 1);
    expect(api.calls, contains('upload:LICENCE:3'));
    expect(find.text('Pending review'), findsOneWidget);
    expect(find.text('1 of 2 required documents uploaded'), findsOneWidget);
  });

  testWidgets('cancelling the picker uploads nothing', (t) async {
    final api = FakeDriverApi();
    await _open(t, api: api, picker: FakePicker(null));
    await _openDocuments(t);
    await t.tap(find.widgetWithText(AppButton, 'Upload').first);
    await t.pumpAndSettle();
    expect(api.calls.where((c) => c.startsWith('upload')), isEmpty);
  });

  testWidgets('an upload the server refuses shows the reason and keeps the document list', (t) async {
    final api = FakeDriverApi()..uploadError = const ApiException('File is larger than 5 MB', statusCode: 413);
    await _open(t, api: api);
    await _openDocuments(t);
    await t.tap(find.widgetWithText(AppButton, 'Upload').first);
    await t.pumpAndSettle();
    expect(find.text('File is larger than 5 MB'), findsOneWidget);
    expect(find.text('Not uploaded'), findsNWidgets(3));
  });

  testWidgets('the documents screen fits a small phone', (t) async {
    reduceMotionFor(t, size: const Size(320, 568));
    Fakes(storedRole: UserRole.driver, driver: FakeAuthRepository(UserRole.driver, hasToken: true)).install();
    await t.pumpWidget(const RideFreelyApp());
    await t.pumpAndSettle();
    await _openDocuments(t);
    expect(t.takeException(), isNull);
  });

  test('controller does not start a second upload while one is running', () async {
    final api = FakeDriverApi();
    final c = DocumentsController(api, FakePicker());
    await Future.wait([c.upload('LICENCE'), c.upload('LICENCE')]);
    expect(api.calls.where((x) => x.startsWith('upload')).length, 1);
  });

  testWidgets('screen can be built without the app shell', (t) async {
    reduceMotionFor(t);
    Fakes(storedRole: UserRole.driver).install();
    await t.pumpWidget(GetMaterialApp(home: RoleTheme(role: UserRole.driver, child: const DocumentsPage())));
    await t.pumpAndSettle();
    expect(find.text('Driving licence'), findsOneWidget);
  });
}
