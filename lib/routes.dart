import 'core/core.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const role = '/role';

  static String login(UserRole r) => '/${r.name}/login';
  static String register(UserRole r) => '/${r.name}/register';
  static String home(UserRole r) => '/${r.name}/home';

  static const documents = '/driver/documents';

  // Customer-only screens
  static const drivers = '/customer/drivers';
  static const driverDetails = '/customer/driver';
  static const book = '/customer/book';
  static const bookingConfirmed = '/customer/confirmed';
  static const tracking = '/customer/tracking';
}
