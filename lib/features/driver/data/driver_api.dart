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

abstract class DriverApi {
  Future<void> setAvailability(bool online);
  Future<void> sendLocation(GeoPoint point);
  Future<List<DriverDocument>> documents();
  Future<void> uploadDocument({required String type, required List<int> bytes, required String filename, required String contentType});
}

class HttpDriverApi implements DriverApi {
  HttpDriverApi(this._client);

  final ApiClient _client;

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
