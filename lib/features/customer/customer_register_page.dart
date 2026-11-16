import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../auth/register_form.dart';

class CustomerRegisterPage extends StatelessWidget {
  const CustomerRegisterPage({super.key});

  @override
  Widget build(BuildContext context) => const RegisterForm(
        role: UserRole.customer,
        title: 'Create your account',
        subtitle: 'Get started in minutes. Hire a verified driver whenever you would rather not drive.',
      );
}
