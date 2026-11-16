import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:ride_freely/core/core.dart';
import 'package:ride_freely/features/customer/profile_form_controller.dart';

import '../core/fake_adapter.dart';

const _form = {
  'version': 2,
  'fields': [
    {'key': 'default_address', 'label': 'Home address', 'field_type': 'text', 'required': false},
  ],
};

({ProfileFormController c, FakeAdapter adapter}) _setup(Handler h) {
  final adapter = FakeAdapter(h);
  final client = ApiClient(baseUrl: 'http://test/api/v1', storage: MemoryTokenStorage(), adapter: adapter);
  return (c: ProfileFormController(client), adapter: adapter);
}

void main() {
  test('load fetches the customer form and the saved answers', () async {
    final s = _setup((o) => o.path == '/forms/customer'
        ? (status: 200, body: _form)
        : (status: 200, body: {'profile': {'answers': {'default_address': '12 MG Road'}}}));
    await s.c.load();
    expect(s.c.form.value!.version, 2);
    expect(s.c.answers, {'default_address': '12 MG Road'});
    expect(s.c.error.value, isNull);
  });

  test('the form only appears once the saved answers are loaded', () async {
    final s = _setup((o) => o.path == '/forms/customer'
        ? (status: 200, body: _form)
        : (status: 200, body: {'profile': {'answers': {'default_address': '12 MG Road'}}}));
    final seen = <Map<String, String>>[];
    ever(s.c.form, (_) => seen.add(Map.of(s.c.answers)));
    await s.c.load();
    expect(seen, isNotEmpty);
    expect(seen.every((a) => a['default_address'] == '12 MG Road'), isTrue);
  });

  test('save puts the answers and reports success', () async {
    final s = _setup((o) => o.method == 'PUT' ? (status: 200, body: {}) : (status: 200, body: _form));
    expect(await s.c.save({'default_address': 'New Road'}), isTrue);
    final put = s.adapter.requests.singleWhere((r) => r.method == 'PUT');
    expect(put.path, '/customers/profile');
    expect(put.data, {'answers': {'default_address': 'New Road'}});
  });

  test('a refused save keeps the field errors and returns false', () async {
    final s = _setup((o) => (status: 422, body: {'detail': [{'loc': ['answers', 'default_address'], 'msg': 'This cannot be empty', 'type': 'value_error'}]}));
    expect(await s.c.save({'default_address': ' '}), isFalse);
    expect(s.c.fieldErrors, {'default_address': 'This cannot be empty'});
  });

  test('a failed load shows the message and leaves no form', () async {
    final s = _setup((o) => (status: 500, body: {'detail': 'Boom'}));
    await s.c.load();
    expect(s.c.form.value, isNull);
    expect(s.c.error.value, 'Boom');
  });
}
