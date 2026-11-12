import 'package:dio/dio.dart';

import '../../../core/core.dart';

enum DocumentStatus { pending, approved, rejected }

class DriverDocument {
  const DriverDocument({required this.type, required this.status, this.note});

  factory DriverDocument.fromJson(Map<String, dynamic> j) => DriverDocument(
        type: j['doc_type'] as String,
        status: DocumentStatus.values.firstWhere(
          (s) => s.name == (j['status'] as String).toLowerCase(),
          orElse: () => DocumentStatus.pending,
        ),
        note: j['review_note'] as String?,
      );

  final String type;
  final DocumentStatus status;
  final String? note;
}

class EarningsPeriod {
  const EarningsPeriod({required this.trips, required this.amount});

  factory EarningsPeriod.fromJson(Map<String, dynamic> j) => EarningsPeriod(trips: (j['trips'] as num).toInt(), amount: j['amount'].toString());

  final int trips;

  /// Money stays text exactly as the server sent it.
  final String amount;
}

/// Completed-trip counts and booking totals. These are booking prices, not payouts.
class Earnings {
  const Earnings({required this.today, required this.week, required this.month, required this.total});

  factory Earnings.fromJson(Map<String, dynamic> j) => Earnings(
        today: EarningsPeriod.fromJson(j['today'] as Map<String, dynamic>),
        week: EarningsPeriod.fromJson(j['week'] as Map<String, dynamic>),
        month: EarningsPeriod.fromJson(j['month'] as Map<String, dynamic>),
        total: EarningsPeriod.fromJson(j['total'] as Map<String, dynamic>),
      );

  static const empty = Earnings(
    today: EarningsPeriod(trips: 0, amount: '0.00'),
    week: EarningsPeriod(trips: 0, amount: '0.00'),
    month: EarningsPeriod(trips: 0, amount: '0.00'),
    total: EarningsPeriod(trips: 0, amount: '0.00'),
  );

  final EarningsPeriod today;
  final EarningsPeriod week;
  final EarningsPeriod month;
  final EarningsPeriod total;
}

abstract class DriverApi {
  Future<Earnings> earnings();
  Future<void> setAvailability(bool online);
  Future<void> sendLocation(GeoPoint point);
  Future<List<DriverDocument>> documents();
  Future<void> uploadDocument({required String type, required List<int> bytes, required String filename, required String contentType});
}

class HttpDriverApi implements DriverApi {
  HttpDriverApi(this._client);

  final ApiClient _client;

  @override
  Future<Earnings> earnings() async => Earnings.fromJson(await _client.getJson('/drivers/earnings'));

  @override
  Future<void> setAvailability(bool online) =>
      _client.patchJson('/drivers/availability', {'status': online ? 'AVAILABLE' : 'OFFLINE'});

  @override
  Future<void> sendLocation(GeoPoint p) => _client.postJson('/locations/update', {
        'latitude': p.latitude,
        'longitude': p.longitude,
        if (p.accuracy != null) 'accuracy': p.accuracy,
        if (p.heading != null) 'heading': p.heading,
        if (p.speed != null) 'speed': p.speed,
      });

  @override
  Future<List<DriverDocument>> documents() async =>
      (await _client.getList('/drivers/documents')).cast<Map<String, dynamic>>().map(DriverDocument.fromJson).toList();

  @override
  Future<void> uploadDocument({required String type, required List<int> bytes, required String filename, required String contentType}) {
    final form = FormData.fromMap({
      'doc_type': type,
      'file': MultipartFile.fromBytes(bytes, filename: filename, contentType: DioMediaType.parse(contentType)),
    });
    return _client.postForm('/drivers/documents', form);
  }
}
