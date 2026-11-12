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

  /// Who is showing the list right now (and whether they can be seen). Polling runs while anyone is.
  final _watchers = <Object, bool Function()>{};
  bool _appActive = true;

  /// Bumped whenever an action changes the list, so a slower load answered later cannot overwrite it.
  int _version = 0;

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
  /// a refresh ([keepItems]) leaves it on screen. A [quiet] load (polling) also leaves the loading flag and
  /// error alone, and a failure of a refresh never blanks a list that is already showing.
  Future<void> load({bool keepItems = false, bool quiet = false}) async {
    final started = _version;
    if (!quiet) {
      loading.value = true;
      error.value = null;
    }
    if (!keepItems) items.clear();
    try {
      final fresh = await _api.list();
      if (started == _version) items.assignAll(fresh);
    } catch (e) {
      if (keepItems && items.isNotEmpty) {
        // A good list is already showing: a refresh that fails must not blank it.
        if (!quiet) actionError.value = _message(e);
      } else {
        items.clear();
        error.value = _message(e);
      }
    } finally {
      if (!quiet) loading.value = false;
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
      _version++;
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
    _version++;
    try {
      final updated = await call();
      _version++;
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

  /// A list on screen registers here. Polling runs while at least one watcher is registered, and stops
  /// when the last one leaves, so one widget going away cannot stop another's polling.
  void attach(Object watcher, {bool Function()? visible}) {
    _watchers[watcher] = visible ?? () => true;
    _timer ??= Timer.periodic(pollInterval, (_) => _poll());
  }

  void detach(Object watcher) {
    _watchers.remove(watcher);
    if (_watchers.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// The app went to the background (false) or came back (true; reloads once).
  void setAppActive(bool active) {
    if (active == _appActive) return;
    _appActive = active;
    if (active) _poll();
  }

  /// Skipped while backgrounded, while something is loading or an action runs, or when no watcher can be seen.
  void _poll() {
    if (!_appActive || actingId.value != null || loading.value) return;
    if (!_watchers.values.any((visible) => visible())) return;
    load(keepItems: true, quiet: true);
  }

  @override
  void onClose() {
    _timer?.cancel();
    _timer = null;
    super.onClose();
  }
}

BookingsController bookingsFor(UserRole role) =>
    Get.find<BookingsController>(tag: role.name);
