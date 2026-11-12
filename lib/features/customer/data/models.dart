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
  });

  final String id;
  final String name;
  final double rating;
  final int rides;
  final double hourlyRate;
  final int experienceYears;
  final bool verified;
  final bool available;
  final String? about;
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
