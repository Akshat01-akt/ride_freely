import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:ride_freely/app.dart';
import 'package:ride_freely/core/core.dart';
import 'package:ride_freely/features/customer/data/models.dart';
import 'package:ride_freely/features/customer/data/sources.dart';
import 'package:ride_freely/routes.dart';

import '../fakes.dart';

const _amit = DriverSummary(id: 'a', name: 'Amit Kumar', rating: 4.9, rides: 1200, hourlyRate: 140, experienceYears: 8, verified: true, available: true, about: 'Safe and punctual.');
const _vikash = DriverSummary(id: 'b', name: 'Vikash Sharma', rating: 4.5, rides: 90, hourlyRate: 110, experienceYears: 3, verified: false, available: true);

Future<void> _pump(WidgetTester t, {List<DriverSummary> drivers = const [], WalletSource? wallet, Size size = const Size(390, 844)}) async {
  reduceMotionFor(t, size: size);
  Fakes(
    storedRole: UserRole.customer,
    customer: FakeAuthRepository(UserRole.customer, hasToken: true),
    drivers: drivers,
    wallet: wallet,
  ).install();
  await t.pumpWidget(const RideFreelyApp());
  await t.pumpAndSettle();
}

Future<void> _openDrivers(WidgetTester t) async {
  final target = find.text('Book now').first;
  // The greeting card pushes the banner below the fold on a small phone; scroll until it can be tapped.
  for (var i = 0; i < 6 && target.hitTestable().evaluate().isEmpty; i++) {
    await t.drag(find.byType(ListView).first, const Offset(0, -200));
    await t.pumpAndSettle();
  }
  await t.tap(target);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('home shows real drivers from the source', (t) async {
    await _pump(t, drivers: [_amit, _vikash]);
    expect(find.text('Popular drivers'), findsOneWidget);
    expect(find.text('Amit Kumar'), findsOneWidget);
  });

  testWidgets('home shows an honest empty state when there are no drivers', (t) async {
    await _pump(t);
    expect(find.text('No drivers nearby yet'), findsOneWidget);
    expect(find.text('Amit Kumar'), findsNothing);
  });

  testWidgets('banner opens the available drivers screen', (t) async {
    await _pump(t, drivers: [_amit]);
    await _openDrivers(t);
    expect(find.text('Available drivers'), findsOneWidget);
  });

  testWidgets('verified filter hides unverified drivers and search narrows by name', (t) async {
    await _pump(t, drivers: [_amit, _vikash]);
    await _openDrivers(t);
    expect(find.text('Vikash Sharma'), findsOneWidget);
    await t.tap(find.text('Verified'));
    await t.pumpAndSettle();
    expect(find.text('Vikash Sharma'), findsNothing);
    expect(find.text('Amit Kumar'), findsOneWidget);
    await t.tap(find.text('All'));
    await t.enterText(find.byType(TextField), 'vik');
    await t.pumpAndSettle();
    expect(find.text('Amit Kumar'), findsNothing);
    expect(find.text('Vikash Sharma'), findsOneWidget);
  });

  testWidgets('a search with no match explains what to do', (t) async {
    await _pump(t, drivers: [_amit]);
    await _openDrivers(t);
    await t.enterText(find.byType(TextField), 'zzz');
    await t.pumpAndSettle();
    expect(find.text('No drivers match'), findsOneWidget);
  });

  testWidgets('lowest price sorts cheapest first', (t) async {
    await _pump(t, drivers: [_amit, _vikash]);
    await _openDrivers(t);
    await t.drag(find.text('Top rated'), const Offset(-300, 0));
    await t.pumpAndSettle();
    await t.tap(find.text('Lowest price'));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.text('Vikash Sharma')).dy, lessThan(t.getTopLeft(find.text('Amit Kumar')).dy));
  });

  testWidgets('driver details show the profile and booking is honest that it is not live yet', (t) async {
    await _pump(t, drivers: [_amit]);
    await _openDrivers(t);
    await t.tap(find.text('Amit Kumar'));
    await t.pumpAndSettle();
    expect(find.text('Safe and punctual.'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    await t.tap(find.widgetWithText(AppButton, 'Book now'));
    await t.pump();
    expect(find.textContaining('Booking opens in the next release'), findsOneWidget);
  });

  testWidgets('expandable sections open and close', (t) async {
    await _pump(t, drivers: [_amit]);
    await _openDrivers(t);
    await t.tap(find.text('Amit Kumar'));
    await t.pumpAndSettle();
    expect(find.textContaining('Choose a start time'), findsNothing);
    await t.tap(find.text('How booking works'));
    await t.pumpAndSettle();
    expect(find.textContaining('Choose a start time'), findsOneWidget);
  });

  testWidgets('booking confirmation leads to tracking, which fakes no location or ETA', (t) async {
    await _pump(t);
    Get.toNamed(Routes.bookingConfirmed, arguments: const BookingSummary(id: 'DR1', driver: _amit, status: BookingStatus.assigned));
    await t.pumpAndSettle();
    expect(find.text('Booking confirmed!'), findsOneWidget);
    expect(find.text('#DR1'), findsOneWidget);
    await t.tap(find.text('Track ride'));
    await t.pumpAndSettle();
    expect(find.text("Waiting for your driver's live location."), findsOneWidget);
    expect(find.textContaining('Arriving in'), findsNothing);
  });

  testWidgets('tracking shows ETA only when the booking carries one', (t) async {
    await _pump(t);
    Get.toNamed(Routes.tracking, arguments: const BookingSummary(id: 'DR1', driver: _amit, status: BookingStatus.onTheWay, etaMinutes: 5, distanceKm: 1.8));
    await t.pumpAndSettle();
    expect(find.text('Arriving in 5 min • 1.8 km'), findsOneWidget);
    expect(find.text('On the way'), findsOneWidget);
  });

  testWidgets('wallet shows an empty state with no data', (t) async {
    await _pump(t);
    await t.tap(find.text('Wallet'));
    await t.pumpAndSettle();
    expect(find.text('₹0'), findsOneWidget);
    expect(find.text('No transactions yet'), findsOneWidget);
  });

  testWidgets('wallet shows balance and transactions from the source', (t) async {
    await _pump(
      t,
      wallet: FakeWalletSource(data: const WalletData(balance: 850, transactions: [WalletTransaction(title: 'Wallet top-up', date: 'Nov 08, 2026', amount: 500)])),
    );
    await t.tap(find.text('Wallet'));
    await t.pumpAndSettle();
    expect(find.text('₹850'), findsOneWidget);
    expect(find.text('+₹500'), findsOneWidget);
  });

  testWidgets('bookings tab lists real bookings and switches to Past', (t) async {
    await _pump(t, wallet: FakeWalletSource(bookingList: const [BookingSummary(id: 'DR9', driver: _amit, status: BookingStatus.onTheWay)]));
    await t.tap(find.text('Bookings'));
    await t.pumpAndSettle();
    expect(find.text('Booking #DR9'), findsOneWidget);
    await t.tap(find.text('Past'));
    await t.pumpAndSettle();
    expect(find.text('No past bookings'), findsOneWidget);
  });

  testWidgets('profile menu jumps to the wallet tab', (t) async {
    await _pump(t);
    await t.tap(find.text('Profile'));
    await t.pumpAndSettle();
    await t.tap(find.text('Wallet & payments'));
    await t.pumpAndSettle();
    expect(find.text('My wallet'), findsOneWidget);
  });

  testWidgets('screens fit a small 320x568 phone without overflow', (t) async {
    await _pump(t, drivers: [_amit, _vikash], size: const Size(320, 568));
    expect(t.takeException(), isNull);
    for (final tab in ['Bookings', 'Wallet', 'Profile', 'Home']) {
      await t.tap(find.text(tab));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: tab);
    }
    await _openDrivers(t);
    expect(t.takeException(), isNull);
    await t.tap(find.text('Amit Kumar'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
