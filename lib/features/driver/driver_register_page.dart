import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/core.dart';

import '../../routes.dart';
import '../auth/auth_scaffold.dart';
import '../auth/validators.dart';
import '../auth/server_help.dart';

class DriverRegisterPage extends StatefulWidget {
  const DriverRegisterPage({super.key});

  @override
  State<DriverRegisterPage> createState() => _DriverRegisterPageState();
}

class _DriverRegisterPageState extends State<DriverRegisterPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _licence = TextEditingController();
  final _experience = TextEditingController();
  final _rate = TextEditingController();
  final _password = TextEditingController();
  final _auth = authFor(UserRole.driver);

  @override
  void initState() {
    super.initState();
    _auth.error.value = null;
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _licence, _experience, _rate, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final email = _email.text.trim();
    final ok = await _auth.register({
      'full_name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'password': _password.text,
      if (email.isNotEmpty) 'email': email,
      'licence_number': _licence.text.trim(),
      'experience_years': int.parse(_experience.text.trim()),
      'hourly_rate': _rate.text.trim(),
    });
    if (ok) Get.offAllNamed(Routes.home(UserRole.driver));
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        showBack: true,
        title: 'Register as a driver',
        subtitle: 'Tell us about yourself. Our team verifies your documents before you go live.',
        children: [
          Form(
            key: _form,
            child: Column(
              children: [
                AppTextField(
                  key: const Key('name'),
                  controller: _name,
                  label: 'Full name',
                  icon: Icons.person_rounded,
                  validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your name' : null,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  key: const Key('phone'),
                  controller: _phone,
                  label: 'Phone number',
                  icon: Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                  validator: requiredPhone,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  key: const Key('email'),
                  controller: _email,
                  label: 'Email (optional)',
                  icon: Icons.mail_rounded,
                  keyboardType: TextInputType.emailAddress,
                  validator: optionalEmail,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  key: const Key('licence'),
                  controller: _licence,
                  label: 'Driving licence number',
                  icon: Icons.badge_rounded,
                  validator: (v) => (v ?? '').trim().length < 3 ? 'Enter your licence number' : null,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  key: const Key('experience'),
                  controller: _experience,
                  label: 'Years of driving experience',
                  icon: Icons.timeline_rounded,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    return n == null || n < 0 || n > 60 ? 'Enter a number from 0 to 60' : null;
                  },
                ),
                const SizedBox(height: 16),
                AppTextField(
                  key: const Key('hourly_rate'),
                  controller: _rate,
                  label: 'Hourly rate (₹)',
                  icon: Icons.currency_rupee_rounded,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    final n = double.tryParse((v ?? '').trim());
                    return n == null || n <= 0 ? 'Enter a rate above 0' : null;
                  },
                ),
                const SizedBox(height: 16),
                AppTextField(
                  key: const Key('password'),
                  controller: _password,
                  label: 'Create password',
                  icon: Icons.lock_rounded,
                  obscure: true,
                  textInputAction: TextInputAction.done,
                  validator: (v) => (v ?? '').length < 8 ? 'Use at least 8 characters' : null,
                ),
              ],
            ),
          ),
          Obx(() => FormError(_auth.error.value)),
          ServerHelp(auth: _auth),
          const SizedBox(height: 16),
          Obx(() => AppButton(label: 'Create account', loading: _auth.isLoading.value, onPressed: _submit)),
        ],
      );
}
