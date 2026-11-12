import '../../core/core.dart';
import 'booking_models.dart';

abstract class BookingsApi {
  Future<List<Booking>> list();
  Future<Booking> create({
    required String driverId,
    required BookingType type,
    DateTime? start,
    int? hours,
    required String address,
    String? notes,
  });
  Future<Booking> act(String id, BookingAction action);
}

class HttpBookingsApi implements BookingsApi {
  HttpBookingsApi(this._client);

  final ApiClient _client;

  @override
  Future<List<Booking>> list() async =>
      (await _client.getList('/bookings')).cast<Map<String, dynamic>>().map(Booking.fromJson).toList();

  @override
  Future<Booking> create({
    required String driverId,
    required BookingType type,
    DateTime? start,
    int? hours,
    required String address,
    String? notes,
  }) async {
    final trimmed = notes?.trim() ?? '';
    final json = await _client.postJson('/bookings', {
      'driver_id': driverId,
      'booking_type': type == BookingType.fullDay ? 'FULL_DAY' : 'HOURLY',
      // Missing start means "now" on the server.
      if (start != null) 'start_time': start.toUtc().toIso8601String(),
      if (type == BookingType.hourly && hours != null) 'hours': hours,
      'pickup_address': address.trim(),
      if (trimmed.isNotEmpty) 'notes': trimmed,
    });
    return Booking.fromJson(json);
  }

  @override
  Future<Booking> act(String id, BookingAction action) async =>
      Booking.fromJson(await _client.postJson('/bookings/$id/${action.name}', {}));
}
