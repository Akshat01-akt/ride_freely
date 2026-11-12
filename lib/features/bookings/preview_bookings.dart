import 'booking_models.dart';
import 'bookings_api.dart';

/// Sample bookings for design review only (see `kUiPreview`). Actions change them in memory, nothing is sent anywhere.
class PreviewBookingsApi implements BookingsApi {
  PreviewBookingsApi()
    : _items = [
        sample(id: 'p1'),
        sample(id: 'p2', state: BookingState.accepted, hoursFromNow: 30),
        sample(id: 'p3', state: BookingState.completed, hoursFromNow: -48),
      ];

  static Booking sample({
    String id = 'p1',
    BookingState state = BookingState.requested,
    int hoursFromNow = 26,
    int? rating,
  }) {
    final start = DateTime.now().toUtc().add(Duration(hours: hoursFromNow));
    return Booking(
      id: id,
      state: state,
      type: BookingType.hourly,
      start: start,
      end: start.add(const Duration(hours: 2)),
      hours: 2,
      price: '280.00',
      address: '12 MG Road, Kanpur',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
      driverId: 'p1',
      driverName: 'Amit Kumar',
      customerName: 'Asha Rao',
      driverPhone: state == BookingState.accepted ? '+919800000001' : null,
      customerPhone: state == BookingState.accepted ? '+919800000002' : null,
      rating: rating,
    );
  }

  List<Booking> _items;

  @override
  Future<List<Booking>> list() async => _items;

  @override
  Future<Booking> create({
    required String driverId,
    required BookingType type,
    DateTime? start,
    int? hours,
    required String address,
    String? notes,
  }) async {
    final b = sample(id: 'p${_items.length + 1}');
    _items = [b, ..._items];
    return b;
  }

  @override
  Future<Booking> rate(String id, int stars) async {
    final old = _items.firstWhere((b) => b.id == id);
    final updated = sample(id: id, state: old.state, rating: stars);
    _items = [for (final b in _items) b.id == id ? updated : b];
    return updated;
  }

  @override
  Future<Booking> act(String id, BookingAction action) async {
    final old = _items.firstWhere((b) => b.id == id);
    final next = switch (action) {
      BookingAction.cancel => BookingState.cancelled,
      BookingAction.accept => BookingState.accepted,
      BookingAction.reject => BookingState.rejected,
      BookingAction.start => BookingState.inProgress,
      BookingAction.complete => BookingState.completed,
    };
    final updated = sample(id: id, state: next);
    _items = [for (final b in _items) b.id == id ? updated : b];
    return old.id == updated.id ? updated : old;
  }
}
