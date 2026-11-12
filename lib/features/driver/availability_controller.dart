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

  bool get sending => _timer != null;

  Future<void> setOnline(bool want) async {
    if (busy.value) return;
    busy.value = true;
    error.value = null;
    try {
      want ? await _goOnline() : await _goOffline();
    } finally {
      busy.value = false;
    }
  }

  Future<void> _goOnline() async {
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
    online.value = true;
    _startSending();
    await sendOnce();
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
    try {
      final point = await _location.current();
      await _api.sendLocation(point);
      warning.value = null;
    } on LocationException catch (e) {
      warning.value = e.message;
    } on ApiException catch (e) {
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
    }
  }

  void _startSending() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => sendOnce());
  }

  void _stopSending() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void onClose() {
    _stopSending();
    super.onClose();
  }
}
