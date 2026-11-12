class DriverSummary {
  const DriverSummary({
    required this.id,
    required this.name,
    required this.rating,
    required this.rides,
    required this.hourlyRate,
    required this.experienceYears,
    required this.verified,
    required this.available,
    this.about,
    this.distanceMeters,
  });

  factory DriverSummary.fromJson(Map<String, dynamic> j) => DriverSummary(
        id: j['id'] as String,
        name: j['name'] as String,
        rating: double.tryParse('${j['rating']}') ?? 0,
        rides: 0, // the server does not report ride counts yet
        hourlyRate: double.tryParse('${j['hourly_rate']}') ?? 0,
        experienceYears: (j['experience_years'] as num?)?.toInt() ?? 0,
        verified: j['verified'] as bool? ?? false,
        available: true, // the nearby search only returns available drivers
        distanceMeters: (j['distance_meters'] as num?)?.toDouble(),
      );

  final String id;
  final String name;
  final double rating;
  final int rides;
  final double hourlyRate;
  final int experienceYears;
  final bool verified;
  final bool available;
  final String? about;

  /// Straight-line distance from the customer. Exact driver coordinates are never sent to customers.
  final double? distanceMeters;

  String? get distanceLabel {
    final d = distanceMeters;
    if (d == null) return null;
    return d < 1000 ? '${d.round()} m away' : '${(d / 1000).toStringAsFixed(1)} km away';
  }
}

enum BookingStatus { assigned, onTheWay, arrived }

class BookingSummary {
  const BookingSummary({required this.id, required this.driver, required this.status, this.etaMinutes, this.distanceKm});

  final String id;
  final DriverSummary driver;
  final BookingStatus status;
  final int? etaMinutes;
  final double? distanceKm;
}

class WalletTransaction {
  const WalletTransaction({required this.title, required this.date, required this.amount});

  final String title;
  final String date;

  /// Negative for payments, positive for top-ups.
  final double amount;
}

class WalletData {
  const WalletData({this.balance = 0, this.transactions = const []});

  final double balance;
  final List<WalletTransaction> transactions;
}
