import 'package:get/get.dart';
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_freely/core/core.dart';
import 'package:ride_freely/features/bookings/bookings.dart';
import 'package:ride_freely/features/customer/data/models.dart';
import 'package:ride_freely/features/driver/availability_controller.dart';
import 'package:ride_freely/features/driver/data/driver_api.dart';
import 'package:ride_freely/features/driver/documents_controller.dart';
import 'package:ride_freely/features/driver/earnings.dart';
import 'package:ride_freely/features/customer/data/sources.dart';

/// Continuous animations never settle, so tests run with the OS reduce-motion setting on.
void reduceMotionFor(WidgetTester t, {Size size = const Size(390, 844)}) {
  t.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
  // Lists build lazily, so tests need a phone-sized window rather than the 800x600 default.
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

class FakeLocationService implements LocationService {
  FakeLocationService({
    this.point = const GeoPoint(latitude: 26.4499, longitude: 80.3319),
    this.error,
  });

  GeoPoint point;
  LocationException? error;
  int calls = 0;
  int settingsOpened = 0;
  final prompts = <bool>[];

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<GeoPoint> current({bool prompt = true}) async {
    calls++;
    prompts.add(prompt);
    if (error != null) throw error!;
    return point;
  }
}

class FakeDriverApi implements DriverApi {
  final calls = <String>[];
  ApiException? availabilityError;
  ApiException? locationError;
  ApiException? uploadError;
  ApiException? documentsError;
  List<DriverDocument> docs = const [];
  Earnings earningsData = Earnings.empty;
  ApiException? earningsError;
  int earningsCalls = 0;

  /// When set, setAvailability / sendLocation wait for it, so tests can interleave calls.
  Completer<void>? availabilityGate;
  Completer<void>? sendGate;

  @override
  Future<void> setAvailability(bool online) async {
    calls.add('setAvailability:$online');
    await availabilityGate?.future;
    if (availabilityError != null) throw availabilityError!;
  }

  @override
  Future<void> sendLocation(GeoPoint point) async {
    calls.add('sendLocation');
    await sendGate?.future;
    if (locationError != null) throw locationError!;
  }

  @override
  Future<Earnings> earnings() async {
    earningsCalls++;
    if (earningsError != null) throw earningsError!;
    return earningsData;
  }

  @override
  Future<List<DriverDocument>> documents() async {
    if (documentsError != null) throw documentsError!;
    return docs;
  }

  @override
  Future<void> uploadDocument({
    required String type,
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    calls.add('upload:$type:${bytes.length}');
    if (uploadError != null) throw uploadError!;
    docs = [
      ...docs.where((d) => d.type != type),
      DriverDocument(type: type, status: DocumentStatus.pending),
    ];
  }
}

class FakePicker implements DocumentPicker {
  FakePicker([
    this.file = const PickedDocument(
      bytes: [1, 2, 3],
      filename: 'photo.jpg',
      contentType: 'image/jpeg',
    ),
  ]);

  PickedDocument? file;
  int calls = 0;

  @override
  Future<PickedDocument?> pick() async {
    calls++;
    return file;
  }
}

class FakeDriversSource implements DriversSource {
  FakeDriversSource(this.drivers);
  List<DriverSummary> drivers;
  Object? error;
  int calls = 0;

  @override
  Future<List<DriverSummary>> nearby() async {
    calls++;
    if (error != null) throw error!;
    return drivers;
  }
}

class FakeBookingsApi implements BookingsApi {
  FakeBookingsApi([List<Booking>? items]) : items = items ?? [];

  static Booking booking({
    String id = 'b1',
    BookingState state = BookingState.requested,
    String driver = 'Ravi Kumar',
    String customer = 'Asha Rao',
    String? driverPhone,
    String? customerPhone,
    String? notes,
    int? rating,
  }) => Booking(
    id: id,
    state: state,
    type: BookingType.hourly,
    start: DateTime.utc(2030, 1, 5, 10),
    end: DateTime.utc(2030, 1, 5, 12),
    hours: 2,
    price: '360.00',
    address: '12 MG Road',
    expiresAt: DateTime.utc(2030, 1, 1, 10, 10),
    driverId: 'd1',
    driverName: driver,
    customerName: customer,
    driverPhone: driverPhone,
    customerPhone: customerPhone,
    notes: notes,
    rating: rating,
  );

  List<Booking> items;
  Object? error;
  Object? actError;
  Completer<void>? gate;
  int actCalls = 0;
  int listCalls = 0;
  Completer<void>? listGate;
  final created = <Map<String, Object?>>[];
  final rated = <String>[];
  final actions = <String>[];

  @override
  Future<List<Booking>> list() async {
    listCalls++;
    final snapshot = items; // what the server knew when the request was answered
    await listGate?.future;
    if (error != null) throw error!;
    return snapshot;
  }

  @override
  Future<Booking> create({
    required String driverId,
    required BookingType type,
    DateTime? start,
    int? hours,
    required String address,
    String? notes,
  }) async {
    created.add({
      'driverId': driverId,
      'type': type,
      'start': start,
      'hours': hours,
      'address': address,
      'notes': notes,
    });
    if (error != null) throw error!;
    final b = booking(id: 'new${created.length}');
    items = [b, ...items];
    return b;
  }

  @override
  Future<Booking> rate(String id, int stars) async {
    rated.add('$id:$stars');
    if (actError != null) throw actError!;
    final old = items.firstWhere((b) => b.id == id);
    final updated = booking(id: id, state: old.state, driver: old.driverName, customer: old.customerName, rating: stars);
    items = [for (final b in items) b.id == id ? updated : b];
    return updated;
  }

  @override
  Future<Booking> act(String id, BookingAction action) async {
    actCalls++;
    actions.add('$id:${action.name}');
    await gate?.future;
    if (actError != null) throw actError!;
    final next = switch (action) {
      BookingAction.cancel => BookingState.cancelled,
      BookingAction.accept => BookingState.accepted,
      BookingAction.reject => BookingState.rejected,
      BookingAction.start => BookingState.inProgress,
      BookingAction.complete => BookingState.completed,
    };
    final old = items.firstWhere((b) => b.id == id);
    final updated = booking(
      id: id,
      state: next,
      driver: old.driverName,
      customer: old.customerName,
    );
    items = [for (final b in items) b.id == id ? updated : b];
    return updated;
  }
}

class FakeWalletSource implements WalletSource {
  FakeWalletSource({
    this.data = const WalletData(),
    this.bookingList = const [],
  });
  final WalletData data;
  final List<BookingSummary> bookingList;

  @override
  Future<WalletData> load() async => data;

  @override
  Future<List<BookingSummary>> bookings() async => bookingList;
}

/// Repository that never touches the network.
class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository(
    UserRole role, {
    this.hasToken = false,
    this.loginError,
    this.loginException,
    this.registerException,
    this.verification = 'PENDING',
  }) : super(
         ApiClient(baseUrl: 'http://fake', storage: MemoryTokenStorage()),
         role,
       );

  final bool hasToken;
  final String? loginError;

  /// Throws this exact exception on login (for example a connection failure).
  final ApiException? loginException;
  final ApiException? registerException;
  final String verification;
  int loginCalls = 0;
  int registerCalls = 0;
  Map<String, dynamic>? lastRegister;

  @override
  Future<bool> hasSession() async => hasToken;

  @override
  Future<void> login(String phone, String password) async {
    loginCalls++;
    if (loginException != null) throw loginException!;
    if (loginError != null) throw ApiException(loginError!, statusCode: 401);
  }

  @override
  Future<void> register(Map<String, dynamic> fields) async {
    registerCalls++;
    lastRegister = fields;
    if (registerException != null) throw registerException!;
  }

  @override
  Future<Map<String, dynamic>> me() async => role == UserRole.driver
      ? {
          'full_name': 'Ravi Kumar',
          'phone': '+919876500000',
          'licence_number': 'DL-123',
          'experience_years': 6,
          'hourly_rate': '180.00',
          'verification_status': verification,
          'availability_status': 'OFFLINE',
          'rating': '0.00',
        }
      : {'full_name': 'Asha Rao', 'phone': '+919876543210', 'email': null};

  @override
  Future<void> logout() async {}
}

class Fakes {
  Fakes({
    UserRole? storedRole,
    FakeAuthRepository? customer,
    FakeAuthRepository? driver,
    this.onboardingDone = true,
    FakeDriverApi? driverApi,
    FakeLocationService? location,
    FakePicker? picker,
    List<DriverSummary> drivers = const [],
    Object? driversError,
    WalletSource? wallet,
    FakeBookingsApi? customerBookings,
    FakeBookingsApi? driverBookings,
    this.pollInterval = const Duration(hours: 1),
  }) : customerBookings = customerBookings ?? FakeBookingsApi(),
       driverBookings = driverBookings ?? FakeBookingsApi(),
       driverApi = driverApi ?? FakeDriverApi(),
       location = location ?? FakeLocationService(),
       picker = picker ?? FakePicker(),
       driversSource = FakeDriversSource(drivers)..error = driversError,
       walletSource = wallet ?? FakeWalletSource(),
       customer = customer ?? FakeAuthRepository(UserRole.customer),
       driver = driver ?? FakeAuthRepository(UserRole.driver),
       roleStore = MemoryRoleStore(storedRole);

  final bool onboardingDone;
  final Duration pollInterval;
  final FakeBookingsApi customerBookings;
  final FakeBookingsApi driverBookings;
  final FakeDriverApi driverApi;
  final FakeLocationService location;
  final FakePicker picker;
  final FakeDriversSource driversSource;
  final WalletSource walletSource;
  final ServerConfig serverConfig = ServerConfig(
    defaultUrl: 'http://default.test/api/v1',
    store: MemoryServerStore(),
    clients: [],
  );
  final FakeAuthRepository customer;
  final FakeAuthRepository driver;
  final MemoryRoleStore roleStore;

  void install() {
    Get.reset();
    // Closing controllers cancels the location timer, which would otherwise outlive the test.
    addTearDown(() => Get.deleteAll(force: true));
    Get.put<RoleStore>(roleStore);
    Get.put<ServerConfig>(serverConfig);
    Get.put<OnboardingStore>(MemoryOnboardingStore(onboardingDone));
    Get.put<DriverApi>(driverApi);
    Get.put<LocationService>(location);
    Get.put<DocumentPicker>(picker);
    Get.put(
      AvailabilityController(
        driverApi,
        location,
        interval: const Duration(hours: 1),
      ),
    );
    Get.put(DocumentsController(driverApi, picker));
    Get.put(DriversController(driversSource));
    Get.put(WalletController(walletSource));
    Get.put(BookingsController(customerBookings, pollInterval: pollInterval), tag: UserRole.customer.name);
    Get.put(BookingsController(driverBookings, pollInterval: pollInterval), tag: UserRole.driver.name);
    Get.put(EarningsController(driverApi));
    Get.put(AuthController(customer), tag: UserRole.customer.name);
    Get.put(AuthController(driver), tag: UserRole.driver.name);
  }
}
