import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../auth/register_form.dart';

class DriverRegisterPage extends StatelessWidget {
  const DriverRegisterPage({super.key});

  @override
  Widget build(BuildContext context) => const RegisterForm(
        role: UserRole.driver,
        title: 'Register as a driver',
        subtitle: 'Create your account first. Next you will add your details and documents for our team to verify.',
      );
}
