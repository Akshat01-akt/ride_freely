import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_freely/core/core.dart';
import 'package:ride_freely/features/driver/data/driver_api.dart';

import 'fake_adapter.dart';

({HttpDriverApi api, FakeAdapter adapter}) _setup(Handler h) {
  final adapter = FakeAdapter(h);
  final client = ApiClient(baseUrl: 'http://test/api/v1', storage: MemoryTokenStorage(), adapter: adapter);
  return (api: HttpDriverApi(client), adapter: adapter);
}

void main() {
  test('going online sends AVAILABLE and offline sends OFFLINE', () async {
    final s = _setup((o) => (status: 200, body: {'availability_status': 'AVAILABLE'}));
    await s.api.setAvailability(true);
    await s.api.setAvailability(false);
    expect(s.adapter.requests.map((r) => r.method), ['PATCH', 'PATCH']);
    expect(s.adapter.requests.map((r) => r.path), ['/drivers/availability', '/drivers/availability']);
    expect(s.adapter.requests.map((r) => (r.data as Map)['status']), ['AVAILABLE', 'OFFLINE']);
  });

  test('sendLocation posts latitude and longitude and tolerates the empty 204 reply', () async {
    final s = _setup((o) => (status: 204, body: {}));
    await s.api.sendLocation(const GeoPoint(latitude: 26.45, longitude: 80.33, accuracy: 8));
    final sent = s.adapter.requests.single.data as Map;
    expect(s.adapter.requests.single.path, '/locations/update');
    expect(sent['latitude'], 26.45);
    expect(sent['longitude'], 80.33);
    expect(sent['accuracy'], 8);
    expect(sent.containsKey('heading'), isFalse);
  });

  test('documents are parsed with their status and review note', () async {
    final s = _setup((o) => (
          status: 200,
          body: [
            {'id': '1', 'doc_type': 'LICENCE', 'status': 'REJECTED', 'review_note': 'Blurry'},
            {'id': '2', 'doc_type': 'ID_PROOF', 'status': 'PENDING', 'review_note': null},
          ],
        ));
    final docs = await s.api.documents();
    expect(docs.map((d) => d.type), ['LICENCE', 'ID_PROOF']);
    expect(docs.first.status, DocumentStatus.rejected);
    expect(docs.first.note, 'Blurry');
    expect(docs.last.status, DocumentStatus.pending);
  });

  test('upload sends a multipart form with the document type', () async {
    final s = _setup((o) => (status: 201, body: {'id': '1', 'doc_type': 'LICENCE', 'status': 'PENDING'}));
    await s.api.uploadDocument(type: 'LICENCE', bytes: [1, 2, 3], filename: 'l.png', contentType: 'image/png');
    final form = s.adapter.requests.single.data as FormData;
    expect(s.adapter.requests.single.path, '/drivers/documents');
    expect(form.fields.single.key, 'doc_type');
    expect(form.fields.single.value, 'LICENCE');
    expect(form.files.single.key, 'file');
  });

  test('server errors become ApiException with the server message', () async {
    final s = _setup((o) => (status: 403, body: {'detail': 'Your documents must be approved before you can go online'}));
    await expectLater(
      s.api.setAvailability(true),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('approved'))),
    );
  });
}
