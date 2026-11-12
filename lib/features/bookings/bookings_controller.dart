import 'dart:async';

import 'package:get/get.dart';

import '../../core/core.dart';
import 'booking_models.dart';
import 'bookings_api.dart';

/// One per role (customer or driver): the signed-in person's bookings and the actions they may take.
class BookingsController extends GetxController {
  BookingsController(this._api, {this.pollInterval = const Duration(seconds: 30)});

  /// How often an open list reloads by itself. There is no server push yet.
  final Duration pollInterval;
  Timer? _timer;

  final BookingsApi _api;
  final items = <Booking>[].obs;
  final loading = false.obs;

  /// Why the list could not be loaded.
  final error = RxnString();

  /// Why the last create or action was refused.
  final actionError = RxnString();

  /// The booking an action is running on; blocks a second tap.
  final actingId = RxnString();

  List<Booking> get upcoming => items.where((b) => b.state.isActive).toList();
  List<Booking> get past => items.where((b) => !b.state.isActive).toList();

  static String _message(Object e) =>
      e is ApiException ? e.message : 'Something went wrong. Please try again.';

  /// Loads the list. A plain load clears the old one first (it may belong to a previous account);
  /// a refresh ([keepItems]) leaves it on screen while the new one arrives.
  Future<void> load({bool keepItems = false}) async {
    loading.value = true;
    error.value = null;
    if (!keepItems) items.clear();
    try {
      items.assignAll(await _api.list());
    } catch (e) {
      items.clear();
      error.value = _message(e);
    } finally {
      loading.value = false;
    }
  }

  Future<Booking?> create({
    required String driverId,
    required BookingType type,
    DateTime? start,
    int? hours,
    required String address,
    String? notes,
  }) async {
    if (actingId.value != null) return null;
    actingId.value = 'new';
    actionError.value = null;
    try {
      final booking = await _api.create(
        driverId: driverId,
        type: type,
        start: start,
        hours: hours,
        address: address,
        notes: notes,
      );
      items.insert(0, booking);
      return booking;
    } catch (e) {
      actionError.value = _message(e);
      return null;
    } finally {
      actingId.value = null;
    }
  }

  Future<bool> act(String id, BookingAction action) => _run(id, () => _api.act(id, action));

  Future<bool> rate(String id, int stars) => _run(id, () => _api.rate(id, stars));

  Future<bool> _run(String id, Future<Booking> Function() call) async {
    if (actingId.value != null) return false;
    actingId.value = id;
    actionError.value = null;
    try {
      final updated = await call();
      final i = items.indexWhere((b) => b.id == id);
      if (i >= 0) items[i] = updated;
      return true;
    } catch (e) {
      actionError.value = _message(e);
      // The booking probably changed under us (expired, cancelled): show what it really is now.
      await load(keepItems: true); // actingId stays set until this finishes, so no second tap sneaks in
      return false;
    } finally {
      actingId.value = null;
    }
  }

  /// Reloads every [pollInterval] while a list is on screen; skipped while something is loading or an action runs.
  void startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) {
      if (actingId.value == null && !loading.value) {
        load(keepItems: true);
      }
    });
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void onClose() {
    stopPolling();
    super.onClose();
  }
}

BookingsController bookingsFor(UserRole role) =>
    Get.find<BookingsController>(tag: role.name);
