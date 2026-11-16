import 'package:flutter_test/flutter_test.dart';
import 'package:ride_freely/features/auth/validators.dart';

void main() {
  test('accepts the spellings the server accepts', () {
    for (final ok in ['9876543210', '98765 43210', '+91 98765 43210', '919876543210', '09876543210']) {
      expect(requiredPhone(ok), isNull, reason: ok);
    }
  });

  test('rejects empty, short and non-mobile numbers', () {
    expect(requiredPhone(''), 'Enter your phone number');
    for (final bad in ['12345', '5876543210', '+1 234 567 8901', '98765432101234']) {
      expect(requiredPhone(bad), isNotNull, reason: bad);
    }
  });

  test('identifier accepts an email address or an Indian mobile number', () {
    for (final ok in ['asha@example.com', ' asha@example.com ', '98765 43210', '+91 98765 43210']) {
      expect(requiredIdentifier(ok), isNull, reason: ok);
    }
  });

  test('identifier rejects empty and garbage', () {
    expect(requiredIdentifier(''), 'Enter your email or mobile number');
    expect(requiredIdentifier('   '), 'Enter your email or mobile number');
    for (final bad in ['asha@', '@example.com', 'asha@example', '12345', 'hello']) {
      expect(requiredIdentifier(bad), isNotNull, reason: bad);
    }
  });

  test('identifier fields pick email or phone', () {
    expect(identifierFields(' a@b.co '), {'email': 'a@b.co'});
    expect(identifierFields('98765 43210'), {'phone': '98765 43210'});
  });
}
