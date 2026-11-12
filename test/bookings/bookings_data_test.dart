import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:ride_freely/core/core.dart';
import 'package:ride_freely/features/bookings/bookings.dart';

import '../core/fake_adapter.dart';
import '../fakes.dart';

Map<String, dynamic> _json({
  String status = 'REQUESTED',
  Map<String, dynamic>? driver,
  Map<String, dynamic>? customer,
}) => {
  'id': 'b1',
  'status': status,
  'booking_type': 'HOURLY',
  'start_time': '2030-01-05T10:00:00Z',
  'end_time': '2030-01-05T12:00:00Z',
  'hours': 2,
  'price_amount': '360.00',
  'pickup_address': '12 MG Road',
  'expires_at': '2030-01-01T10:10:00Z',
  'driver': driver ?? {'id': 'd1', 'name': 'Ravi Kumar'},
  'customer': customer ?? {'name': 'Asha Rao'},
};

({HttpBookingsApi api, FakeAdapter adapter}) _make(Handler h) {
  final adapter = FakeAdapter(h);
  final client = ApiClient(
    baseUrl: 'http://test/api/v1',
    storage: MemoryTokenStorage(),
    adapter: adapter,
  );
  return (api: HttpBookingsApi(client), adapter: adapter);
}

void main() {
  group('Booking.fromJson', () {
    test('maps every field, keeps price as text and times in UTC', () {
      final b = Booking.fromJson(_json());
      expect(b.id, 'b1');
      expect(b.state, BookingState.requested);
      expect(b.type, BookingType.hourly);
      expect(b.hours, 2);
      expect(b.price, '360.00');
      expect(b.address, '12 MG Road');
      expect(b.notes, isNull);
      expect(b.start.isUtc, isTrue);
      expect(b.end.difference(b.start), const Duration(hours: 2));
      expect(b.driverId, 'd1');
      expect(b.driverName, 'Ravi Kumar');
      expect(b.customerName, 'Asha Rao');
      expect(b.driverPhone, isNull);
      expect(b.customerPhone, isNull);
    });

    test('phones appear when the server sends them', () {
      final b = Booking.fromJson(
        _json(
          status: 'ACCEPTED',
          driver: {'id': 'd1', 'name': 'R', 'phone': '+919876500000'},
          customer: {'name': 'A', 'phone': '+919876543210'},
        ),
      );
      expect(b.state, BookingState.accepted);
      expect(b.driverPhone, '+919876500000');
      expect(b.customerPhone, '+919876543210');
    });

    test(
      'every server status maps, and an unknown one is not silently treated as active',
      () {
        for (final (s, st) in [
          ('REQUESTED', BookingState.requested),
          ('ACCEPTED', BookingState.accepted),
          ('REJECTED', BookingState.rejected),
          ('CANCELLED', BookingState.cancelled),
          ('EXPIRED', BookingState.expired),
          ('IN_PROGRESS', BookingState.inProgress),
          ('COMPLETED', BookingState.completed),
        ]) {
          expect(Booking.fromJson(_json(status: s)).state, st);
        }
        expect(
          Booking.fromJson(_json(status: 'SOMETHING_NEW')).state,
          BookingState.unknown,
        );
        expect(BookingState.unknown.isActive, isFalse);
      },
    );

    test('active states are requested, accepted and in progress', () {
      expect(BookingState.values.where((s) => s.isActive), [
        BookingState.requested,
        BookingState.accepted,
        BookingState.inProgress,
      ]);
    });
  });

  group('HttpBookingsApi', () {
    test('list reads /bookings', () async {
      final m = _make((o) => (status: 200, body: [_json()]));
      final list = await m.api.list();
      expect(m.adapter.requests.single.path, '/bookings');
      expect(list.single.id, 'b1');
    });

    test('create sends an hourly request with a UTC start', () async {
      final m = _make((o) => (status: 201, body: _json()));
      final start = DateTime.utc(2030, 1, 5, 10);
      await m.api.create(
        driverId: 'd1',
        type: BookingType.hourly,
        start: start,
        hours: 2,
        address: '12 MG Road',
        notes: 'gate 3',
      );
      final req = m.adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/bookings');
      expect(req.data, {
        'driver_id': 'd1',
        'booking_type': 'HOURLY',
        'start_time': '2030-01-05T10:00:00.000Z',
        'hours': 2,
        'pickup_address': '12 MG Road',
        'notes': 'gate 3',
      });
    });

    test(
      'a book-now full-day request omits start, hours and empty notes',
      () async {
        final m = _make((o) => (status: 201, body: _json()));
        await m.api.create(
          driverId: 'd1',
          type: BookingType.fullDay,
          address: 'Home',
          notes: '  ',
        );
        expect(m.adapter.requests.single.data, {
          'driver_id': 'd1',
          'booking_type': 'FULL_DAY',
          'pickup_address': 'Home',
        });
      },
    );

    test('actions post to the booking action path', () async {
      final m = _make((o) => (status: 200, body: _json(status: 'ACCEPTED')));
      for (final a in BookingAction.values) {
        await m.api.act('b1', a);
      }
      expect(m.adapter.requests.map((r) => r.path), [
        for (final a in BookingAction.values) '/bookings/b1/${a.name}',
      ]);
      expect(BookingAction.values.map((a) => a.name), [
        'cancel',
        'accept',
        'reject',
        'start',
        'complete',
      ]);
    });
  });

  group('BookingsController', () {
    tearDown(() => Get.deleteAll(force: true));

    test('load fills the list and splits upcoming from past', () async {
      final api = FakeBookingsApi([
        FakeBookingsApi.booking(id: 'a', state: BookingState.requested),
        FakeBookingsApi.booking(id: 'b', state: BookingState.completed),
        FakeBookingsApi.booking(id: 'c', state: BookingState.cancelled),
      ]);
      final c = BookingsController(api);
      await c.load();
      expect(c.upcoming.map((b) => b.id), ['a']);
      expect(c.past.map((b) => b.id), ['b', 'c']);
      expect(c.loading.value, isFalse);
      expect(c.error.value, isNull);
    });

    test('a failed load shows the message and clears the old list', () async {
      final api = FakeBookingsApi([FakeBookingsApi.booking(id: 'a')]);
      final c = BookingsController(api);
      await c.load();
      api.error = const ApiException(
        'Cannot reach the server. Check your connection and try again.',
      );
      await c.load();
      expect(c.error.value, contains('Cannot reach'));
      expect(c.items, isEmpty);
    });

    test('create returns the booking and puts it first', () async {
      final api = FakeBookingsApi([FakeBookingsApi.booking(id: 'old')]);
      final c = BookingsController(api);
      await c.load();
      final b = await c.create(
        driverId: 'd1',
        type: BookingType.hourly,
        hours: 2,
        address: 'X',
      );
      expect(b, isNotNull);
      expect(c.items.first.id, b!.id);
      expect(c.items.length, 2);
    });

    test('create reports the server message and returns null', () async {
      final api = FakeBookingsApi([])
        ..error = const ApiException(
          'The driver already has a booking at that time',
          statusCode: 409,
        );
      final c = BookingsController(api);
      expect(
        await c.create(
          driverId: 'd1',
          type: BookingType.hourly,
          hours: 2,
          address: 'X',
        ),
        isNull,
      );
      expect(
        c.actionError.value,
        'The driver already has a booking at that time',
      );
    });

    test(
      'act replaces the booking with the server version and clears busy',
      () async {
        final api = FakeBookingsApi([FakeBookingsApi.booking(id: 'a')]);
        final c = BookingsController(api);
        await c.load();
        expect(await c.act('a', BookingAction.accept), isTrue);
        expect(c.items.single.state, BookingState.accepted);
        expect(c.actingId.value, isNull);
      },
    );

    test('a refused action shows why and reloads the real state', () async {
      final api = FakeBookingsApi([FakeBookingsApi.booking(id: 'a')]);
      final c = BookingsController(api);
      await c.load();
      api.actError = const ApiException(
        'This booking cannot be changed that way right now',
        statusCode: 409,
      );
      api.items = [
        FakeBookingsApi.booking(id: 'a', state: BookingState.expired),
      ];
      expect(await c.act('a', BookingAction.accept), isFalse);
      expect(c.actionError.value, contains('cannot be changed'));
      expect(c.items.single.state, BookingState.expired);
    });

    test('a second tap while an action is running is ignored', () async {
      final api = FakeBookingsApi([FakeBookingsApi.booking(id: 'a')]);
      final c = BookingsController(api);
      await c.load();
      final first = c.act('a', BookingAction.accept);
      expect(await c.act('a', BookingAction.accept), isFalse);
      await first;
      expect(api.actCalls, 1);
    });

    test('a fresh load hides the previous account\'s bookings until the new ones arrive', () async {
      final api = FakeBookingsApi([FakeBookingsApi.booking(id: 'old')]);
      final c = BookingsController(api);
      await c.load();
      api.listGate = Completer<void>();
      api.items = [FakeBookingsApi.booking(id: 'new')];
      final loading = c.load();
      expect(c.items, isEmpty);
      api.listGate!.complete();
      await loading;
      expect(c.items.single.id, 'new');
    });

    test('a refresh keeps the list on screen while it reloads', () async {
      final api = FakeBookingsApi([FakeBookingsApi.booking(id: 'a')]);
      final c = BookingsController(api);
      await c.load();
      api.listGate = Completer<void>();
      final refreshing = c.load(keepItems: true);
      expect(c.items.single.id, 'a');
      api.listGate!.complete();
      await refreshing;
    });

    test('no second action can start while the reload after a refused action is running', () async {
      final api = FakeBookingsApi([FakeBookingsApi.booking(id: 'a')]);
      final c = BookingsController(api);
      await c.load();
      api.actError = const ApiException('nope', statusCode: 409);
      api.listGate = Completer<void>();
      final first = c.act('a', BookingAction.accept);
      await Future<void>.delayed(Duration.zero);
      expect(c.actingId.value, 'a');
      expect(await c.act('a', BookingAction.accept), isFalse);
      api.listGate!.complete();
      await first;
      expect(c.actingId.value, isNull);
    });
  });
}
