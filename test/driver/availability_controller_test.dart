import 'package:flutter_test/flutter_test.dart';
import 'package:ride_freely/core/core.dart';
import 'package:ride_freely/features/driver/availability_controller.dart';

import '../fakes.dart';

({AvailabilityController c, FakeDriverApi api, FakeLocationService loc}) _make({Duration interval = const Duration(hours: 1)}) {
  final api = FakeDriverApi();
  final loc = FakeLocationService();
  return (c: AvailabilityController(api, loc, interval: interval), api: api, loc: loc);
}

void main() {
  test('going online checks location, tells the server, and starts sharing the position', () async {
    final m = _make();
    await m.c.setOnline(true);
    expect(m.api.calls, ['setAvailability:true', 'sendLocation']);
    expect(m.c.online.value, isTrue);
    expect(m.c.sending, isTrue);
    expect(m.c.error.value, isNull);
    m.c.onClose();
  });

  test('a server rejection leaves the driver offline with the server message', () async {
    final m = _make();
    m.api.availabilityError = const ApiException('Your documents must be approved before you can go online', statusCode: 403);
    await m.c.setOnline(true);
    expect(m.c.online.value, isFalse);
    expect(m.c.sending, isFalse);
    expect(m.c.error.value, contains('approved'));
    expect(m.api.calls, ['setAvailability:true']);
  });

  test('denied location permission keeps the driver offline and never calls the server', () async {
    final m = _make();
    m.loc.error = const LocationException(LocationProblem.denied);
    await m.c.setOnline(true);
    expect(m.c.online.value, isFalse);
    expect(m.api.calls, isEmpty);
    expect(m.c.error.value, contains('permission'));
  });

  test('going offline tells the server and stops sharing', () async {
    final m = _make();
    await m.c.setOnline(true);
    m.api.calls.clear();
    await m.c.setOnline(false);
    expect(m.api.calls, ['setAvailability:false']);
    expect(m.c.online.value, isFalse);
    expect(m.c.sending, isFalse);
  });

  test('if the server cannot be reached while going offline we still stop sharing and say so', () async {
    final m = _make();
    await m.c.setOnline(true);
    m.api.availabilityError = const ApiException('Cannot reach the server. Check your connection and try again.');
    await m.c.setOnline(false);
    expect(m.c.sending, isFalse);
    expect(m.c.online.value, isFalse);
    expect(m.c.error.value, contains('Cannot reach'));
  });

  test('a position update the server refuses (for example after suspension) takes the driver offline', () async {
    final m = _make();
    await m.c.setOnline(true);
    m.api.locationError = const ApiException('Go online before sharing your location', statusCode: 409);
    await m.c.sendOnce();
    expect(m.c.online.value, isFalse);
    expect(m.c.sending, isFalse);
    expect(m.c.error.value, contains('Go online'));
  });

  test('a temporary location or network failure keeps the driver online and shows a warning that clears', () async {
    final m = _make();
    await m.c.setOnline(true);
    m.loc.error = const LocationException(LocationProblem.unavailable);
    await m.c.sendOnce();
    expect(m.c.online.value, isTrue);
    expect(m.c.warning.value, isNotNull);
    m.loc.error = null;
    await m.c.sendOnce();
    expect(m.c.warning.value, isNull);
    m.api.locationError = const ApiException('Cannot reach the server. Check your connection and try again.');
    await m.c.sendOnce();
    expect(m.c.online.value, isTrue);
    expect(m.c.warning.value, isNotNull);
    m.c.onClose();
  });

  test('resuming a session the server still shows as AVAILABLE restarts sharing', () async {
    final m = _make();
    await m.c.resumeIfAvailable('AVAILABLE');
    expect(m.c.online.value, isTrue);
    expect(m.c.sending, isTrue);
    expect(m.api.calls, ['sendLocation']);
    m.c.onClose();
  });

  test('resuming with any other server state does nothing', () async {
    final m = _make();
    for (final s in ['OFFLINE', 'SUSPENDED', null]) {
      await m.c.resumeIfAvailable(s);
    }
    expect(m.c.online.value, isFalse);
    expect(m.api.calls, isEmpty);
  });

  test('positions are sent on the timer and stop after the controller is closed', () async {
    final m = _make(interval: const Duration(milliseconds: 20));
    await m.c.setOnline(true);
    await Future<void>.delayed(const Duration(milliseconds: 90));
    final sent = m.api.calls.where((c) => c == 'sendLocation').length;
    expect(sent, greaterThanOrEqualTo(3));
    m.c.onClose();
    final after = m.api.calls.length;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(m.api.calls.length, after);
  });

  test('tapping the switch twice quickly does not send two requests', () async {
    final m = _make();
    await Future.wait([m.c.setOnline(true), m.c.setOnline(true)]);
    expect(m.api.calls.where((c) => c == 'setAvailability:true').length, 1);
    m.c.onClose();
  });
}
