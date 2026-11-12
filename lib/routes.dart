import 'core/core.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const role = '/role';

  static String login(UserRole r) => '/${r.name}/login';
  static String register(UserRole r) => '/${r.name}/register';
  static String home(UserRole r) => '/${r.name}/home';
}
