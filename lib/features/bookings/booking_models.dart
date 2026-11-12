enum BookingType { hourly, fullDay }

enum BookingState {
  requested,
  accepted,
  rejected,
  cancelled,
  expired,
  inProgress,
  completed,

  /// A status this app version does not know; shown, but never treated as active.
  unknown;

  /// Holds the driver's time slot.
  bool get isActive => this == requested || this == accepted || this == inProgress;

  static BookingState fromServer(String value) => switch (value) {
    'REQUESTED' => requested,
    'ACCEPTED' => accepted,
    'REJECTED' => rejected,
    'CANCELLED' => cancelled,
    'EXPIRED' => expired,
    'IN_PROGRESS' => inProgress,
    'COMPLETED' => completed,
    _ => unknown,
  };

  String get label => switch (this) {
    requested => 'Waiting for driver',
    accepted => 'Accepted',
    rejected => 'Declined',
    cancelled => 'Cancelled',
    expired => 'Expired',
    inProgress => 'In progress',
    completed => 'Completed',
    unknown => 'Unknown',
  };
}

/// What a person can do to a booking. The name is the server path segment.
enum BookingAction { cancel, accept, reject, start, complete }

class Booking {
  const Booking({
    required this.id,
    required this.state,
    required this.type,
    required this.start,
    required this.end,
    required this.hours,
    required this.price,
    required this.address,
    required this.expiresAt,
    required this.driverId,
    required this.driverName,
    required this.customerName,
    this.notes,
    this.driverPhone,
    this.customerPhone,
  });

  factory Booking.fromJson(Map<String, dynamic> j) {
    final driver = j['driver'] as Map<String, dynamic>;
    final customer = j['customer'] as Map<String, dynamic>;
    return Booking(
      id: j['id'] as String,
      state: BookingState.fromServer(j['status'] as String),
      type: j['booking_type'] == 'FULL_DAY' ? BookingType.fullDay : BookingType.hourly,
      start: DateTime.parse(j['start_time'] as String).toUtc(),
      end: DateTime.parse(j['end_time'] as String).toUtc(),
      hours: (j['hours'] as num).toInt(),
      price: j['price_amount'].toString(),
      address: j['pickup_address'] as String,
      notes: j['notes'] as String?,
      expiresAt: DateTime.parse(j['expires_at'] as String).toUtc(),
      driverId: driver['id'] as String,
      driverName: driver['name'] as String,
      driverPhone: driver['phone'] as String?,
      customerName: customer['name'] as String,
      customerPhone: customer['phone'] as String?,
    );
  }

  final String id;
  final BookingState state;
  final BookingType type;
  final DateTime start;
  final DateTime end;
  final int hours;

  /// Money stays text exactly as the server sent it.
  final String price;
  final String address;
  final String? notes;
  final DateTime expiresAt;
  final String driverId;
  final String driverName;
  final String? driverPhone;
  final String customerName;
  final String? customerPhone;
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// "Sat 5 Jan, 10:00 - 12:00" in the phone's local time.
String formatWindow(DateTime start, DateTime end) {
  final s = start.toLocal(), e = end.toLocal();
  final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
  final day = '${_days[s.weekday - 1]} ${s.day} ${_months[s.month - 1]}';
  return sameDay ? '$day, ${_hm(s)} - ${_hm(e)}' : '$day ${_hm(s)} - ${_days[e.weekday - 1]} ${e.day} ${_months[e.month - 1]} ${_hm(e)}';
}
