import 'package:get/get.dart';

import 'auth_controller.dart';
import 'auth_repository.dart';

/// Each interface has its own session, registered under the role's name.
AuthController authFor(UserRole role) => Get.find<AuthController>(tag: role.name);
