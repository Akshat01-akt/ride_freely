import 'package:get/get.dart';

import '../../../core/core.dart';
import 'models.dart';

/// Where the customer app gets drivers from. The backend endpoint does not exist yet,
/// so [BackendDriversSource] returns nothing; swap its body when `/drivers/nearby` ships.
abstract class DriversSource {
  Future<List<DriverSummary>> nearby();
}

class BackendDriversSource implements DriversSource {
  BackendDriversSource(this._client, this._location, {this.radiusMeters = 5000});

  final ApiClient _client;
  final LocationService _location;
  final double radiusMeters;

  @override
  Future<List<DriverSummary>> nearby() async {
    final here = await _location.current();
    final json = await _client.getJson('/drivers/nearby', query: {
      'latitude': here.latitude,
      'longitude': here.longitude,
      'radius': radiusMeters,
    });
    final list = (json['drivers'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    return list.map(DriverSummary.fromJson).toList();
  }
}

abstract class WalletSource {
  Future<WalletData> load();
  Future<List<BookingSummary>> bookings();
}

class BackendWalletSource implements WalletSource {
  @override
  Future<WalletData> load() async => const WalletData();

  @override
  Future<List<BookingSummary>> bookings() async => const [];
}

/// Sample content for design review only (see `kUiPreview`).
class PreviewData {
  static const drivers = <DriverSummary>[
    DriverSummary(id: 'p1', name: 'Amit Kumar', rating: 4.9, rides: 1200, hourlyRate: 140, experienceYears: 8, verified: true, available: true, about: '8+ years of driving experience. Known for safe and punctual service.'),
    DriverSummary(id: 'p2', name: 'Vikash Sharma', rating: 4.8, rides: 980, hourlyRate: 130, experienceYears: 6, verified: true, available: true, about: 'Calm, courteous and comfortable on city and highway routes.'),
    DriverSummary(id: 'p3', name: 'Rohit Yadav', rating: 4.8, rides: 756, hourlyRate: 150, experienceYears: 5, verified: true, available: false, about: 'Prefers long day bookings. Familiar with airport transfers.'),
    DriverSummary(id: 'p4', name: 'Sandeep Patel', rating: 4.7, rides: 620, hourlyRate: 120, experienceYears: 4, verified: false, available: true),
  ];

  static const booking = BookingSummary(id: 'DR123456', driver: DriverSummary(id: 'p1', name: 'Amit Kumar', rating: 4.9, rides: 1200, hourlyRate: 140, experienceYears: 8, verified: true, available: true, about: '8+ years of driving experience. Known for safe and punctual service.'), status: BookingStatus.onTheWay, etaMinutes: 5, distanceKm: 1.8);

  static const transactions = <WalletTransaction>[
    WalletTransaction(title: 'Ride payment', date: 'Nov 10, 2026', amount: -120),
    WalletTransaction(title: 'Wallet top-up', date: 'Nov 08, 2026', amount: 500),
    WalletTransaction(title: 'Ride payment', date: 'Nov 05, 2026', amount: -180),
  ];
}

class PreviewDriversSource implements DriversSource {
  @override
  Future<List<DriverSummary>> nearby() async => PreviewData.drivers;
}

class PreviewWalletSource implements WalletSource {
  @override
  Future<WalletData> load() async => const WalletData(balance: 850, transactions: PreviewData.transactions);

  @override
  Future<List<BookingSummary>> bookings() async => [PreviewData.booking];
}

class DriversController extends GetxController {
  DriversController(this._source);

  final DriversSource _source;
  final drivers = <DriverSummary>[].obs;
  final loading = false.obs;

  /// Why the list could not be loaded, in words the user can act on.
  final error = RxnString();

  /// Set when the cause is the phone's location (permission or services), so the screen can offer settings.
  final problem = Rxn<LocationProblem>();

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    problem.value = null;
    try {
      drivers.assignAll(await _source.nearby());
    } on LocationException catch (e) {
      drivers.clear();
      problem.value = e.problem;
      error.value = e.message;
    } on ApiException catch (e) {
      drivers.clear();
      error.value = e.message;
    } catch (_) {
      drivers.clear();
      error.value = 'Something went wrong. Please try again.';
    } finally {
      loading.value = false;
    }
  }
}

class WalletController extends GetxController {
  WalletController(this._source);

  final WalletSource _source;
  final wallet = const WalletData().obs;
  final bookings = <BookingSummary>[].obs;
  final loading = false.obs;

  Future<void> load() async {
    loading.value = true;
    try {
      wallet.value = await _source.load();
      bookings.assignAll(await _source.bookings());
    } catch (_) {
      wallet.value = const WalletData();
      bookings.clear();
    } finally {
      loading.value = false;
    }
  }
}
