import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:ride_freely/app.dart';
import 'package:ride_freely/core/core.dart';
import 'package:ride_freely/features/bookings/bookings.dart';
import 'package:ride_freely/features/customer/data/models.dart';
import 'package:ride_freely/routes.dart';

import '../fakes.dart';

const _amit = DriverSummary(
  id: 'd1',
  name: 'Amit Kumar',
  rating: 4.8,
  rides: 0,
  hourlyRate: 140,
  experienceYears: 8,
  verified: true,
  available: true,
);

Future<FakeBookingsApi> _customer(
  WidgetTester t, {
  List<Booking> bookings = const [],
  Object? listError,
}) async {
  reduceMotionFor(t);
  final api = FakeBookingsApi([...bookings])..error = listError;
  Fakes(
    storedRole: UserRole.customer,
    customer: FakeAuthRepository(UserRole.customer, hasToken: true),
    customerBookings: api,
    drivers: const [_amit],
  ).install();
  await t.pumpWidget(const RideFreelyApp());
  await t.pumpAndSettle();
  return api;
}

Future<FakeBookingsApi> _driver(
  WidgetTester t, {
  List<Booking> bookings = const [],
}) async {
  reduceMotionFor(t);
  final api = FakeBookingsApi([...bookings]);
  Fakes(
    storedRole: UserRole.driver,
    driver: FakeAuthRepository(
      UserRole.driver,
      hasToken: true,
      verification: 'APPROVED',
    ),
    driverBookings: api,
  ).install();
  await t.pumpWidget(const RideFreelyApp());
  await t.pumpAndSettle();
  return api;
}

Future<void> _drag(WidgetTester t, Finder target) async {
  for (var i = 0; i < 8 && target.hitTestable().evaluate().isEmpty; i++) {
    await t.drag(find.byType(Scrollable).first, const Offset(0, -250));
    await t.pumpAndSettle();
  }
}

Future<void> _openBook(WidgetTester t) async {
  Get.toNamed(Routes.book, arguments: _amit);
  await t.pumpAndSettle();
}

void main() {
  group('book a driver', () {
    testWidgets('the driver page leads to the booking form', (t) async {
      await _customer(t);
      Get.toNamed(Routes.driverDetails, arguments: _amit);
      await t.pumpAndSettle();
      await t.tap(find.text('Book this driver'));
      await t.pumpAndSettle();
      expect(find.text('Book Amit Kumar'), findsOneWidget);
    });

    testWidgets(
      'shows an estimate that follows the hours and the booking type',
      (t) async {
        await _customer(t);
        await _openBook(t);
        expect(find.text('₹280'), findsOneWidget); // 2 hours x 140
        expect(find.text('2 hours'), findsOneWidget);
        await t.tap(find.byTooltip('More hours'));
        await t.pumpAndSettle();
        expect(find.text('₹420'), findsOneWidget);
        await t.tap(find.text('Full day'));
        await t.pumpAndSettle();
        expect(find.text('₹1120'), findsOneWidget); // 8 billed hours
        expect(find.byTooltip('More hours'), findsNothing);
      },
    );

    testWidgets('hours stay between 1 and 12', (t) async {
      await _customer(t);
      await _openBook(t);
      for (var i = 0; i < 3; i++) {
        await t.tap(find.byTooltip('Fewer hours'));
        await t.pumpAndSettle();
      }
      expect(find.text('1 hour'), findsOneWidget);
      for (var i = 0; i < 14; i++) {
        await t.tap(find.byTooltip('More hours'));
        await t.pumpAndSettle();
      }
      expect(find.text('12 hours'), findsOneWidget);
    });

    testWidgets('a missing pickup address is caught before anything is sent', (
      t,
    ) async {
      final api = await _customer(t);
      await _openBook(t);
      await _drag(t, find.text('Send request'));
      await t.tap(find.text('Send request'));
      await t.pumpAndSettle();
      expect(find.text('Enter the pickup address'), findsOneWidget);
      expect(api.created, isEmpty);
    });

    testWidgets(
      'sending the request calls the API and shows the request as sent',
      (t) async {
        final api = await _customer(t);
        await _openBook(t);
        await t.enterText(find.byKey(const Key('address')), '12 MG Road');
        await t.enterText(find.byKey(const Key('notes')), 'Gate 3');
        await _drag(t, find.text('Send request'));
        await t.tap(find.text('Send request'));
        await t.pumpAndSettle();
        expect(api.created.single, {
          'driverId': 'd1',
          'type': BookingType.hourly,
          'start': null,
          'hours': 2,
          'address': '12 MG Road',
          'notes': 'Gate 3',
        });
        expect(find.text('Request sent'), findsOneWidget);
        expect(find.textContaining('Waiting for Ravi Kumar'), findsOneWidget);
        expect(
          find.text('Booking confirmed!'),
          findsNothing,
        ); // a request is not a confirmation
      },
    );

    testWidgets('a refusal from the server is shown and the form stays', (
      t,
    ) async {
      final api = await _customer(t);
      api.error = const ApiException(
        'The driver already has a booking at that time',
        statusCode: 409,
      );
      await _openBook(t);
      await t.enterText(find.byKey(const Key('address')), '12 MG Road');
      await _drag(t, find.text('Send request'));
      await t.tap(find.text('Send request'));
      await t.pumpAndSettle();
      await _drag(t, find.textContaining('already has a booking'));
      expect(find.textContaining('already has a booking'), findsOneWidget);
      expect(find.text('Request sent'), findsNothing);
    });

    testWidgets('choosing a time opens the date picker', (t) async {
      await _customer(t);
      await _openBook(t);
      await t.tap(find.text('Pick a time'));
      await t.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    testWidgets('fits a small phone', (t) async {
      reduceMotionFor(t, size: const Size(320, 568));
      Fakes(
        storedRole: UserRole.customer,
        customer: FakeAuthRepository(UserRole.customer, hasToken: true),
      ).install();
      await t.pumpWidget(const RideFreelyApp());
      await t.pumpAndSettle();
      await _openBook(t);
      expect(t.takeException(), isNull);
    });
  });

  group('customer bookings tab', () {
    Future<void> openTab(WidgetTester t) async {
      await t.tap(find.text('Bookings'));
      await t.pumpAndSettle();
    }

    testWidgets('lists real bookings with status, window, price and address', (
      t,
    ) async {
      await _customer(t, bookings: [FakeBookingsApi.booking()]);
      await openTab(t);
      expect(find.text('Ravi Kumar'), findsOneWidget);
      expect(find.text('Waiting for driver'), findsOneWidget);
      expect(find.textContaining('360.00'), findsOneWidget);
      expect(find.textContaining('12 MG Road'), findsOneWidget);
    });

    testWidgets('an empty list says so honestly', (t) async {
      await _customer(t);
      await openTab(t);
      expect(find.text('No upcoming bookings'), findsOneWidget);
    });

    testWidgets(
      'cancel asks first, then cancels and moves the booking to Past',
      (t) async {
        final api = await _customer(t, bookings: [FakeBookingsApi.booking()]);
        await openTab(t);
        await t.tap(find.text('Cancel booking'));
        await t.pumpAndSettle();
        expect(find.text('Cancel this booking?'), findsOneWidget);
        await t.tap(find.text('Keep it'));
        await t.pumpAndSettle();
        expect(api.actions, isEmpty);
        await t.tap(find.text('Cancel booking'));
        await t.pumpAndSettle();
        await t.tap(find.text('Yes, cancel'));
        await t.pumpAndSettle();
        expect(api.actions, ['b1:cancel']);
        expect(find.text('No upcoming bookings'), findsOneWidget);
        await t.tap(find.text('Past'));
        await t.pumpAndSettle();
        expect(find.text('Cancelled'), findsOneWidget);
      },
    );

    testWidgets('the driver phone appears only once accepted', (t) async {
      await _customer(
        t,
        bookings: [
          FakeBookingsApi.booking(
            state: BookingState.accepted,
            driverPhone: '+919876500000',
          ),
        ],
      );
      await openTab(t);
      expect(find.textContaining('+919876500000'), findsOneWidget);
    });

    testWidgets('a load error is explained with a retry', (t) async {
      final api = await _customer(
        t,
        listError: const ApiException(
          'Cannot reach the server. Check your connection and try again.',
        ),
      );
      await openTab(t);
      expect(find.textContaining('Cannot reach the server'), findsOneWidget);
      api.error = null;
      api.items = [FakeBookingsApi.booking()];
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('Ravi Kumar'), findsOneWidget);
    });
  });

  group('driver requests tab', () {
    Future<void> openTab(WidgetTester t) async {
      await t.tap(find.text('Requests'));
      await t.pumpAndSettle();
    }

    testWidgets('no requests shows an honest empty state', (t) async {
      await _driver(t);
      await openTab(t);
      expect(find.text('No requests yet'), findsOneWidget);
    });

    testWidgets('a request shows who, when, where and how much', (t) async {
      await _driver(t, bookings: [FakeBookingsApi.booking(notes: null)]);
      await openTab(t);
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.textContaining('12 MG Road'), findsOneWidget);
      expect(find.textContaining('360.00'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets(
      'accepting shows the customer phone and offers to start the trip',
      (t) async {
        final api = await _driver(t, bookings: [FakeBookingsApi.booking()]);
        await openTab(t);
        await t.tap(find.text('Accept'));
        await t.pumpAndSettle();
        expect(api.actions, ['b1:accept']);
        expect(find.text('Start trip'), findsOneWidget);
        expect(find.text('Accept'), findsNothing);
      },
    );

    testWidgets('declining removes the request from the active list', (
      t,
    ) async {
      final api = await _driver(t, bookings: [FakeBookingsApi.booking()]);
      await openTab(t);
      await t.tap(find.text('Decline'));
      await t.pumpAndSettle();
      expect(api.actions, ['b1:reject']);
      expect(find.text('Accept'), findsNothing);
    });

    testWidgets('a trip in progress can be completed', (t) async {
      final api = await _driver(
        t,
        bookings: [FakeBookingsApi.booking(state: BookingState.inProgress)],
      );
      await openTab(t);
      await t.tap(find.text('Complete trip'));
      await t.pumpAndSettle();
      expect(api.actions, ['b1:complete']);
    });

    testWidgets('a refused action is explained', (t) async {
      final api = await _driver(t, bookings: [FakeBookingsApi.booking()]);
      api.actError = const ApiException(
        'This booking cannot be changed that way right now',
        statusCode: 409,
      );
      await openTab(t);
      await t.tap(find.text('Accept'));
      await t.pumpAndSettle();
      expect(find.textContaining('cannot be changed'), findsOneWidget);
    });
  });

  group('lists stay fresh', () {
    testWidgets('opening the customer Bookings tab reloads it', (t) async {
      final api = await _customer(t, bookings: [FakeBookingsApi.booking()]);
      final before = api.listCalls;
      await t.tap(find.text('Bookings'));
      await t.pumpAndSettle();
      expect(api.listCalls, before + 1);
    });

    testWidgets('pulling down on the customer list reloads it', (t) async {
      final api = await _customer(t, bookings: [FakeBookingsApi.booking()]);
      await t.tap(find.text('Bookings'));
      await t.pumpAndSettle();
      final before = api.listCalls;
      await t.fling(find.byType(ListView).first, const Offset(0, 300), 1000);
      await t.pumpAndSettle();
      expect(api.listCalls, before + 1);
    });

    testWidgets('opening the driver Requests tab reloads it, so new requests show up', (t) async {
      final api = await _driver(t);
      expect(find.text('No requests yet'), findsNothing); // dashboard is showing
      api.items = [FakeBookingsApi.booking()];
      await t.tap(find.text('Requests'));
      await t.pumpAndSettle();
      expect(find.text('Asha Rao'), findsOneWidget);
    });

    testWidgets('pulling down on the driver list reloads it', (t) async {
      final api = await _driver(t, bookings: [FakeBookingsApi.booking()]);
      await t.tap(find.text('Requests'));
      await t.pumpAndSettle();
      final before = api.listCalls;
      await t.fling(find.byType(ListView).first, const Offset(0, 300), 1000);
      await t.pumpAndSettle();
      expect(api.listCalls, before + 1);
    });
  });
}
