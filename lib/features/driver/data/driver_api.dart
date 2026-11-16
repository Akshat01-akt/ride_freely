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

/// One answer the driver gave, with the reviewer's verdict on it.
class AnswerView {
  const AnswerView({required this.value, required this.status, this.note});

  final String value;
  final String status;
  final String? note;
}

/// The driver's application as the server sees it (the `application` block of GET /drivers/me).
class DriverApplication {
  const DriverApplication({
    this.status = 'NOT_SUBMITTED',
    this.answers = const {},
    this.documents = const {},
    this.needsUpdate = const [],
  });

  factory DriverApplication.fromJson(Map<String, dynamic> j) => DriverApplication(
        status: j['status'] as String,
        answers: {
          for (final a in (j['answers'] as List).cast<Map<String, dynamic>>())
            a['key'] as String: AnswerView(value: a['value'] as String, status: a['status'] as String, note: a['review_note'] as String?),
        },
        documents: {
          for (final d in (j['documents'] as List).cast<Map<String, dynamic>>()) d['doc_type'] as String: DriverDocument.fromJson(d),
        },
        needsUpdate: (j['needs_update'] as List).cast<String>(),
      );

  final String status;
  final Map<String, AnswerView> answers;
  final Map<String, DriverDocument> documents;
  final List<String> needsUpdate;

  /// Keys of items the reviewer sent back.
  Set<String> get flagged => {
        for (final e in answers.entries)
          if (e.value.status == 'REJECTED') e.key,
        for (final e in documents.entries)
          if (e.value.status == DocumentStatus.rejected) e.key,
      };
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
  Future<FormSpec> applicationForm();
  Future<DriverApplication> application();

  /// Sends the answers; a 422 comes back as an [ApiException] whose [ApiException.fieldErrors] names the fields.
  Future<void> submitApplication(Map<String, String> answers);
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
  Future<FormSpec> applicationForm() async => FormSpec.fromJson(await _client.getJson('/forms/driver'));

  @override
  Future<DriverApplication> application() async =>
      DriverApplication.fromJson((await _client.getJson('/drivers/me'))['application'] as Map<String, dynamic>);

  @override
  Future<void> submitApplication(Map<String, String> answers) => _client.postJson('/drivers/application', {'answers': answers});

  @override
  Future<void> uploadDocument({required String type, required List<int> bytes, required String filename, required String contentType}) {
    final form = FormData.fromMap({
      'doc_type': type,
      'file': MultipartFile.fromBytes(bytes, filename: filename, contentType: DioMediaType.parse(contentType)),
    });
    return _client.postForm('/drivers/documents', form);
  }
}
