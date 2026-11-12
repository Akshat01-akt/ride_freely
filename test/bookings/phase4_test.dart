import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:ride_freely/app.dart';
import 'package:ride_freely/core/core.dart';
import 'package:ride_freely/features/bookings/bookings.dart';
import 'package:ride_freely/features/driver/data/driver_api.dart';
import 'package:ride_freely/features/driver/earnings.dart';
import 'package:ride_freely/routes.dart';

import '../core/fake_adapter.dart';
import '../fakes.dart';

Future<FakeBookingsApi> _customer(WidgetTester t, {List<Booking> bookings = const [], Duration poll = const Duration(hours: 1)}) async {
  reduceMotionFor(t);
  final api = FakeBookingsApi([...bookings]);
  Fakes(
    storedRole: UserRole.customer,
    customer: FakeAuthRepository(UserRole.customer, hasToken: true),
    customerBookings: api,
    pollInterval: poll,
  ).install();
  await t.pumpWidget(const RideFreelyApp());
  await t.pumpAndSettle();
  await t.tap(find.text('Bookings'));
  await t.pumpAndSettle();
  return api;
}

Future<({FakeBookingsApi bookings, FakeDriverApi driver})> _driver(WidgetTester t, {Duration poll = const Duration(hours: 1), FakeDriverApi? driverApi}) async {
  reduceMotionFor(t);
  final api = FakeBookingsApi();
  final d = driverApi ?? FakeDriverApi();
  Fakes(
    storedRole: UserRole.driver,
    driver: FakeAuthRepository(UserRole.driver, hasToken: true, verification: 'APPROVED'),
    driverBookings: api,
    driverApi: d,
    pollInterval: poll,
  ).install();
  await t.pumpWidget(const RideFreelyApp());
  await t.pumpAndSettle();
  return (bookings: api, driver: d);
}

void main() {
  group('rating data', () {
    test('Booking.fromJson reads rating when present and null otherwise', () {
      Map<String, dynamic> json(Object? rating) => {
            'id': 'b', 'status': 'COMPLETED', 'booking_type': 'HOURLY', 'start_time': '2030-01-05T10:00:00Z', 'end_time': '2030-01-05T12:00:00Z',
            'hours': 2, 'price_amount': '360.00', 'pickup_address': 'x', 'expires_at': '2030-01-01T10:10:00Z',
            'driver': {'id': 'd', 'name': 'R'}, 'customer': {'name': 'A'}, 'rating': ?rating,
          };
      expect(Booking.fromJson(json(4)).rating, 4);
      expect(Booking.fromJson(json(null)).rating, isNull);
    });

    test('HttpBookingsApi.rate posts the stars', () async {
      final adapter = FakeAdapter((o) => (status: 200, body: {
            'id': 'b1', 'status': 'COMPLETED', 'booking_type': 'HOURLY', 'start_time': '2030-01-05T10:00:00Z', 'end_time': '2030-01-05T12:00:00Z',
            'hours': 2, 'price_amount': '360.00', 'pickup_address': 'x', 'expires_at': '2030-01-01T10:10:00Z', 'rating': 5,
            'driver': {'id': 'd', 'name': 'R'}, 'customer': {'name': 'A'},
          }));
      final api = HttpBookingsApi(ApiClient(baseUrl: 'http://test/api/v1', storage: MemoryTokenStorage(), adapter: adapter));
      final b = await api.rate('b1', 5);
      expect(adapter.requests.single.path, '/bookings/b1/rating');
      expect(adapter.requests.single.data, {'rating': 5});
      expect(b.rating, 5);
    });

    test('controller.rate updates the booking and reports a refusal', () async {
      final api = FakeBookingsApi([FakeBookingsApi.booking(state: BookingState.completed)]);
      final c = BookingsController(api);
      await c.load();
      expect(await c.rate('b1', 4), isTrue);
      expect(c.items.single.rating, 4);
      api.actError = const ApiException('You have already rated this trip', statusCode: 409);
      expect(await c.rate('b1', 2), isFalse);
      expect(c.actionError.value, contains('already rated'));
    });
  });

  group('rate a trip screen', () {
    testWidgets('a completed unrated trip offers to rate it, and sends the stars', (t) async {
      final api = await _customer(t, bookings: [FakeBookingsApi.booking(state: BookingState.completed)]);
      await t.tap(find.text('Past'));
      await t.pumpAndSettle();
      await t.tap(find.text('Rate this trip'));
      await t.pumpAndSettle();
      expect(find.text('How was your trip?'), findsOneWidget);
      await t.tap(find.byTooltip('4 stars'));
      await t.pumpAndSettle();
      await t.tap(find.text('Send rating'));
      await t.pumpAndSettle();
      expect(api.rated, ['b1:4']);
      expect(find.text('Rate this trip'), findsNothing);
      expect(find.text('You rated 4 stars'), findsOneWidget);
    });

    testWidgets('sending needs a star chosen first', (t) async {
      final api = await _customer(t, bookings: [FakeBookingsApi.booking(state: BookingState.completed)]);
      await t.tap(find.text('Past'));
      await t.pumpAndSettle();
      await t.tap(find.text('Rate this trip'));
      await t.pumpAndSettle();
      await t.tap(find.text('Send rating'));
      await t.pumpAndSettle();
      expect(api.rated, isEmpty);
      expect(find.text('How was your trip?'), findsOneWidget);
    });

    testWidgets('an already rated trip shows its stars and no rate button', (t) async {
      await _customer(t, bookings: [FakeBookingsApi.booking(state: BookingState.completed, rating: 5)]);
      await t.tap(find.text('Past'));
      await t.pumpAndSettle();
      expect(find.text('You rated 5 stars'), findsOneWidget);
      expect(find.text('Rate this trip'), findsNothing);
    });

    testWidgets('trips that are not completed cannot be rated', (t) async {
      await _customer(t, bookings: [FakeBookingsApi.booking()]);
      expect(find.text('Rate this trip'), findsNothing);
    });
  });

  group('earnings', () {
    test('Earnings.fromJson keeps amounts as text', () {
      final e = Earnings.fromJson({
        'today': {'trips': 1, 'amount': '180.00'}, 'week': {'trips': 2, 'amount': '360.50'},
        'month': {'trips': 3, 'amount': '900.00'}, 'total': {'trips': 9, 'amount': '2700.00'},
      });
      expect(e.today.trips, 1);
      expect(e.week.amount, '360.50');
      expect(e.total.trips, 9);
    });

    test('HttpDriverApi.earnings reads /drivers/earnings', () async {
      final adapter = FakeAdapter((o) => (status: 200, body: {
            'today': {'trips': 0, 'amount': '0.00'}, 'week': {'trips': 0, 'amount': '0.00'},
            'month': {'trips': 0, 'amount': '0.00'}, 'total': {'trips': 4, 'amount': '720.00'},
          }));
      final api = HttpDriverApi(ApiClient(baseUrl: 'http://test/api/v1', storage: MemoryTokenStorage(), adapter: adapter));
      final e = await api.earnings();
      expect(adapter.requests.single.path, '/drivers/earnings');
      expect(e.total.amount, '720.00');
    });

    testWidgets('a new driver sees honest zeros', (t) async {
      await _driver(t);
      await t.tap(find.text('Earnings'));
      await t.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('₹0.00'), findsNWidgets(4));
      expect(find.textContaining('before any commission'), findsOneWidget);
    });

    testWidgets('real totals are shown', (t) async {
      final d = FakeDriverApi()
        ..earningsData = const Earnings(
          today: EarningsPeriod(trips: 1, amount: '180.00'), week: EarningsPeriod(trips: 2, amount: '360.00'),
          month: EarningsPeriod(trips: 3, amount: '900.00'), total: EarningsPeriod(trips: 9, amount: '2700.00'),
        );
      await _driver(t, driverApi: d);
      await t.tap(find.text('Earnings'));
      await t.pumpAndSettle();
      expect(find.text('₹2700.00'), findsOneWidget);
      expect(find.text('9 trips'), findsOneWidget);
      expect(find.text('1 trip'), findsOneWidget);
    });

    testWidgets('a load error is explained with a retry', (t) async {
      final d = FakeDriverApi()..earningsError = const ApiException('Cannot reach the server. Check your connection and try again.');
      await _driver(t, driverApi: d);
      await t.tap(find.text('Earnings'));
      await t.pumpAndSettle();
      expect(find.textContaining('Cannot reach the server'), findsOneWidget);
      d.earningsError = null;
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('opening the tab reloads the totals', (t) async {
      final d = FakeDriverApi();
      await _driver(t, driverApi: d);
      final before = d.earningsCalls;
      await t.tap(find.text('Earnings'));
      await t.pumpAndSettle();
      expect(d.earningsCalls, before + 1);
    });
  });

  group('polling', () {
    testWidgets('the customer list reloads on its own while the tab is open', (t) async {
      final api = await _customer(t, poll: const Duration(seconds: 30));
      final before = api.listCalls;
      await t.pump(const Duration(seconds: 31));
      await t.pump();
      expect(api.listCalls, before + 1);
    });

    testWidgets('polling stops when the tab is left', (t) async {
      final api = await _customer(t, poll: const Duration(seconds: 30));
      await t.tap(find.text('Home'));
      await t.pumpAndSettle();
      final before = api.listCalls;
      await t.pump(const Duration(seconds: 95));
      expect(api.listCalls, before);
    });

    testWidgets('the driver list picks up a new request without any tap', (t) async {
      final r = await _driver(t, poll: const Duration(seconds: 30));
      await t.tap(find.text('Requests'));
      await t.pumpAndSettle();
      expect(find.text('No requests yet'), findsOneWidget);
      r.bookings.items = [FakeBookingsApi.booking()];
      await t.pump(const Duration(seconds: 31));
      await t.pumpAndSettle();
      expect(find.text('Asha Rao'), findsOneWidget);
    });

    testWidgets('a poll never runs while an action is in flight', (t) async {
      final api = await _customer(t, bookings: [FakeBookingsApi.booking()], poll: const Duration(seconds: 30));
      api.gate = Completer<void>();
      await t.tap(find.text('Cancel booking'));
      await t.pumpAndSettle();
      await t.tap(find.text('Yes, cancel'));
      await t.pump();
      final before = api.listCalls;
      await t.pump(const Duration(seconds: 61));
      expect(api.listCalls, before);
      api.gate!.complete();
      await t.pumpAndSettle();
    });
  });

  group('polling rules (review fixes)', () {
    testWidgets('one watcher leaving does not stop another watcher\'s polling', (t) async {
      reduceMotionFor(t);
      final api = FakeBookingsApi();
      final c = BookingsController(api, pollInterval: const Duration(seconds: 30));
      addTearDown(c.onClose);
      final a = Object(), b = Object();
      c.attach(a);
      c.attach(b);
      c.detach(a);
      await t.pump(const Duration(seconds: 31));
      expect(api.listCalls, 1);
      c.detach(b);
      await t.pump(const Duration(seconds: 61));
      expect(api.listCalls, 1);
    });

    testWidgets('a poll that fails keeps the list and shows no error', (t) async {
      reduceMotionFor(t);
      final api = FakeBookingsApi([FakeBookingsApi.booking()]);
      final c = BookingsController(api, pollInterval: const Duration(seconds: 30));
      addTearDown(c.onClose);
      await c.load();
      api.error = const ApiException('Cannot reach the server. Check your connection and try again.');
      await c.load(keepItems: true, quiet: true);
      expect(c.items.length, 1);
      expect(c.error.value, isNull);
    });

    testWidgets('a poll does not flip the loading flag, so an empty list does not flicker', (t) async {
      reduceMotionFor(t);
      final api = FakeBookingsApi();
      final c = BookingsController(api);
      api.listGate = Completer<void>();
      final poll = c.load(keepItems: true, quiet: true);
      expect(c.loading.value, isFalse);
      api.listGate!.complete();
      await poll;
    });

    testWidgets('a late poll reply never overwrites what an action just changed', (t) async {
      reduceMotionFor(t);
      final api = FakeBookingsApi([FakeBookingsApi.booking()]);
      final c = BookingsController(api);
      await c.load();
      final gate = Completer<void>();
      api.listGate = gate;
      final poll = c.load(keepItems: true, quiet: true); // asked while the booking was still REQUESTED
      api.listGate = null;
      await c.act('b1', BookingAction.cancel);
      gate.complete();
      await poll; // the old answer arrives late
      expect(c.items.single.state, BookingState.cancelled);
    });

    testWidgets('polling does not run while another screen covers the tab', (t) async {
      final api = await _customer(t, poll: const Duration(seconds: 30));
      Get.toNamed(Routes.drivers);
      await t.pumpAndSettle();
      final before = api.listCalls;
      await t.pump(const Duration(seconds: 95));
      expect(api.listCalls, before);
    });

    testWidgets('polling keeps working after View my bookings replaces the screens', (t) async {
      final api = await _customer(t, poll: const Duration(seconds: 30));
      Get.toNamed(Routes.bookingConfirmed, arguments: FakeBookingsApi.booking());
      await t.pumpAndSettle();
      await t.tap(find.text('View my bookings'));
      await t.pumpAndSettle();
      final before = api.listCalls;
      await t.pump(const Duration(seconds: 31));
      await t.pump();
      expect(api.listCalls, greaterThan(before));
    });

    testWidgets('polling survives quick tab switching with animations on', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = FakeBookingsApi([FakeBookingsApi.booking()]);
      Fakes(
        storedRole: UserRole.customer,
        customer: FakeAuthRepository(UserRole.customer, hasToken: true),
        customerBookings: api,
        pollInterval: const Duration(seconds: 30),
      ).install();
      await t.pumpWidget(const RideFreelyApp());
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 500));
      }
      await t.tap(find.text('Bookings'));
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.text('Home'));
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.text('Bookings'));
      await t.pump(const Duration(seconds: 1));
      final before = api.listCalls;
      await t.pump(const Duration(seconds: 31));
      await t.pump();
      expect(api.listCalls, greaterThan(before));
      Get.deleteAll(force: true);
    });
  });

  group('earnings session (review fix)', () {
    test('a plain load clears the previous driver\'s totals; a refresh keeps them', () async {
      final api = FakeDriverApi()..earningsData = const Earnings(
        today: EarningsPeriod(trips: 1, amount: '1.00'), week: EarningsPeriod(trips: 1, amount: '1.00'),
        month: EarningsPeriod(trips: 1, amount: '1.00'), total: EarningsPeriod(trips: 1, amount: '1.00'),
      );
      final c = EarningsController(api);
      await c.load();
      expect(c.data.value, isNotNull);
      final reload = c.load();
      expect(c.data.value, isNull);
      await reload;
      final refresh = c.load(keep: true);
      expect(c.data.value, isNotNull);
      await refresh;
    });
  });
}
