import 'dart:async';

import 'package:get/get.dart';

import '../../core/core.dart';
import 'data/driver_api.dart';

/// Owns the driver's online/offline state and, while online, sends the phone's position
/// to the server on a timer. Foreground only: the position is not sent when the app is closed.
class AvailabilityController extends GetxController {
  AvailabilityController(this._api, this._location, {this.interval = const Duration(seconds: 10)});

  final DriverApi _api;
  final LocationService _location;
  final Duration interval;

  final online = false.obs;
  final busy = false.obs;

  /// A problem that stopped the driver going online (or took them offline).
  final error = RxnString();

  /// A temporary problem while online (no GPS fix, no network). Sharing keeps retrying.
  final warning = RxnString();

  Timer? _timer;

  // Bumped on every online/offline change. A reply that belongs to an earlier session is ignored.
  int _epoch = 0;
  bool _inFlight = false;

  bool get sending => _timer != null;

  Future<void> setOnline(bool want) async {
    if (busy.value) return;
    busy.value = true;
    final epoch = ++_epoch;
    error.value = null;
    try {
      want ? await _goOnline(epoch) : await _goOffline();
    } finally {
      busy.value = false;
    }
  }

  Future<void> _goOnline(int epoch) async {
    try {
      // Check we can get a position before telling the server we are available.
      await _location.current();
      await _api.setAvailability(true);
    } on LocationException catch (e) {
      error.value = e.message;
      return;
    } on ApiException catch (e) {
      error.value = e.message;
      return;
    }
    if (epoch != _epoch) {
      // Logged out (or switched off) while the request was in flight: do not start sharing.
      return;
    }
    online.value = true;
    _startSending();
    await sendOnce();
  }

  /// Stops sharing at once, even if a switch request is still running (used on logout).
  void forceOffline() {
    _epoch++;
    _stopSending();
    online.value = false;
    warning.value = null;
  }

  Future<void> _goOffline() async {
    _stopSending();
    online.value = false;
    warning.value = null;
    try {
      await _api.setAvailability(false);
    } on ApiException catch (e) {
      error.value = e.message;
    }
  }

  /// Called when the dashboard opens: if the server still has us AVAILABLE, keep sharing.
  Future<void> resumeIfAvailable(String? serverState) async {
    if (serverState != 'AVAILABLE' || sending) return;
    online.value = true;
    _startSending();
    await sendOnce();
  }

  Future<void> sendOnce() async {
    if (_inFlight) return; // the previous update has not finished; never overlap
    _inFlight = true;
    final epoch = _epoch;
    try {
      final point = await _location.current(prompt: false);
      await _api.sendLocation(point);
      if (epoch == _epoch) warning.value = null;
    } on LocationException catch (e) {
      if (epoch == _epoch) warning.value = e.message;
    } on ApiException catch (e) {
      if (epoch != _epoch) return;
      final refused = e.statusCode == 403 || e.statusCode == 409;
      if (refused) {
        // The server no longer lets us share (suspended, rejected, or already offline).
        _stopSending();
        online.value = false;
        warning.value = null;
        error.value = e.message;
      } else {
        warning.value = e.message;
      }
    } finally {
      _inFlight = false;
    }
  }

  void _startSending() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => sendOnce());
  }

  void _stopSending() {
    _epoch++;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void onClose() {
    _stopSending();
    super.onClose();
  }
}
