import 'package:get/get.dart';

import '../../core/core.dart';
import 'booking_models.dart';
import 'bookings_api.dart';

/// One per role (customer or driver): the signed-in person's bookings and the actions they may take.
class BookingsController extends GetxController {
  BookingsController(this._api);

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

  Future<void> load() async {
    loading.value = true;
    error.value = null;
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

  Future<bool> act(String id, BookingAction action) async {
    if (actingId.value != null) return false;
    actingId.value = id;
    actionError.value = null;
    try {
      final updated = await _api.act(id, action);
      final i = items.indexWhere((b) => b.id == id);
      if (i >= 0) items[i] = updated;
      return true;
    } catch (e) {
      actionError.value = _message(e);
      // The booking probably changed under us (expired, cancelled): show what it really is now.
      actingId.value = null;
      await load();
      return false;
    } finally {
      actingId.value = null;
    }
  }
}

BookingsController bookingsFor(UserRole role) =>
    Get.find<BookingsController>(tag: role.name);
