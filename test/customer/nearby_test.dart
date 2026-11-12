import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_freely/app.dart';
import 'package:ride_freely/core/core.dart';
import 'package:ride_freely/features/customer/data/models.dart';
import 'package:ride_freely/features/customer/data/sources.dart';

import '../core/fake_adapter.dart';
import '../fakes.dart';

const _payload = {
  'drivers': [
    {'id': 'p1', 'name': 'Amit Kumar', 'hourly_rate': '140.00', 'rating': '4.80', 'experience_years': 8, 'verified': true, 'distance_meters': 997.2},
    {'id': 'p2', 'name': 'Vikash Sharma', 'hourly_rate': '130.50', 'rating': '0.00', 'experience_years': 2, 'verified': true, 'distance_meters': 3050.0},
  ],
};

({BackendDriversSource source, FakeAdapter adapter, FakeLocationService loc}) _make(Handler h) {
  final adapter = FakeAdapter(h);
  final loc = FakeLocationService();
  final client = ApiClient(baseUrl: 'http://test/api/v1', storage: MemoryTokenStorage(), adapter: adapter);
  return (source: BackendDriversSource(client, loc), adapter: adapter, loc: loc);
}

Future<FakeDriversSource> _pump(WidgetTester t, {Object? error, List<DriverSummary> drivers = const [], FakeLocationService? location}) async {
  reduceMotionFor(t);
  final f = Fakes(
    storedRole: UserRole.customer,
    customer: FakeAuthRepository(UserRole.customer, hasToken: true),
    drivers: drivers,
    driversError: error,
    location: location,
  );
  f.install();
  await t.pumpWidget(const RideFreelyApp());
  await t.pumpAndSettle();
  return f.driversSource;
}

/// Scrolls the home list until [target] can be tapped (the list builds lazily).
Future<void> _reveal(WidgetTester t, Finder target) async {
  for (var i = 0; i < 6 && target.hitTestable().evaluate().isEmpty; i++) {
    await t.drag(find.byType(ListView).first, const Offset(0, -300));
    await t.pumpAndSettle();
  }
}

void main() {
  test('source sends the phone position and maps the response', () async {
    final m = _make((o) => (status: 200, body: _payload));
    final drivers = await m.source.nearby();
    final req = m.adapter.requests.single;
    expect(req.path, '/drivers/nearby');
    expect(req.queryParameters['latitude'], 26.4499);
    expect(req.queryParameters['longitude'], 80.3319);
    expect(drivers.map((d) => d.name), ['Amit Kumar', 'Vikash Sharma']);
    expect(drivers.first.hourlyRate, 140.0);
    expect(drivers.first.rating, 4.8);
    expect(drivers.first.distanceMeters, 997.2);
    expect(drivers.last.hourlyRate, 130.5);
    expect(drivers.first.available, isTrue);
  });

  test('an empty server list is an empty result, not an error', () async {
    final m = _make((o) => (status: 200, body: {'drivers': []}));
    expect(await m.source.nearby(), isEmpty);
  });

  test('a location problem is reported and the server is not called', () async {
    final m = _make((o) => (status: 200, body: _payload));
    m.loc.error = const LocationException(LocationProblem.denied);
    await expectLater(m.source.nearby(), throwsA(isA<LocationException>()));
    expect(m.adapter.requests, isEmpty);
  });

  test('server errors surface as ApiException', () async {
    final m = _make((o) => (status: 500, body: {'detail': 'boom'}));
    await expectLater(m.source.nearby(), throwsA(isA<ApiException>()));
  });

  test('controller turns a location problem into a message and clears old drivers', () async {
    final src = FakeDriversSource(const [])..error = const LocationException(LocationProblem.denied);
    final c = DriversController(src);
    await c.load();
    expect(c.problem.value, LocationProblem.denied);
    expect(c.error.value, contains('permission'));
    expect(c.drivers, isEmpty);
    src.error = null;
    src.drivers = const [DriverSummary(id: 'a', name: 'A', rating: 4, rides: 0, hourlyRate: 100, experienceYears: 1, verified: true, available: true)];
    await c.load();
    expect(c.error.value, isNull);
    expect(c.problem.value, isNull);
    expect(c.drivers.length, 1);
  });

  testWidgets('denied permission shows an actionable message and Try again recovers', (t) async {
    final src = await _pump(t, error: const LocationException(LocationProblem.denied));
    await _reveal(t, find.text('Try again'));
    expect(find.textContaining('Location permission is needed'), findsOneWidget);
    expect(find.text('No drivers nearby yet'), findsNothing);
    src.error = null;
    src.drivers = const [DriverSummary(id: 'a', name: 'Amit Kumar', rating: 4.8, rides: 0, hourlyRate: 140, experienceYears: 8, verified: true, available: true, distanceMeters: 997)];
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    await _reveal(t, find.text('Amit Kumar'));
    expect(find.text('Amit Kumar'), findsOneWidget);
    expect(find.textContaining('Location permission is needed'), findsNothing);
  });

  testWidgets('blocked permission offers to open settings', (t) async {
    final loc = FakeLocationService();
    await _pump(t, error: const LocationException(LocationProblem.deniedForever), location: loc);
    await _reveal(t, find.text('Open settings'));
    expect(find.text('Open settings'), findsOneWidget);
    await t.tap(find.text('Open settings'));
    await t.pumpAndSettle();
    expect(loc.settingsOpened, 1);
  });

  testWidgets('a server error shows its message with a retry', (t) async {
    await _pump(t, error: const ApiException('Cannot reach the server. Check your connection and try again.'));
    await _reveal(t, find.text('Try again'));
    expect(find.textContaining('Cannot reach the server'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('real drivers show their distance and hide the ride count the server does not provide', (t) async {
    await _pump(t, drivers: const [DriverSummary(id: 'a', name: 'Amit Kumar', rating: 4.8, rides: 0, hourlyRate: 140, experienceYears: 8, verified: true, available: true, distanceMeters: 1040)]);
    await _reveal(t, find.textContaining('1.0 km away'));
    expect(find.textContaining('1.0 km away'), findsOneWidget);
    expect(find.textContaining('rides'), findsNothing);
  });

  testWidgets('short distances are shown in metres', (t) async {
    await _pump(t, drivers: const [DriverSummary(id: 'a', name: 'Amit Kumar', rating: 4.8, rides: 0, hourlyRate: 140, experienceYears: 8, verified: true, available: true, distanceMeters: 240)]);
    await _reveal(t, find.textContaining('240 m away'));
    expect(find.textContaining('240 m away'), findsOneWidget);
  });
}
