import 'package:flutter_test/flutter_test.dart';
import 'package:ride_freely/core/core.dart';
import 'package:ride_freely/features/driver/application_controller.dart';

import '../fakes.dart';

void main() {
  test('a refused submit reloads the form so a field the admin just added appears', () async {
    final api = FakeDriverApi()..submitError = const ApiException('x', statusCode: 422, fieldErrors: {'badge_no': 'This is required'});
    final auth = AuthController(FakeAuthRepository(UserRole.driver));
    final c = ApplicationController(api, FakePicker(), auth);
    await c.load();
    final before = api.formCalls;
    await c.submit({'licence_number': 'DL-1'});
    expect(api.formCalls, before + 1);
    expect(c.fieldErrors, {'badge_no': 'This is required'});
    expect(c.submitted.value, isFalse);
  });
}
