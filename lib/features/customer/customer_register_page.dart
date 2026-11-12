import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/core.dart';

import '../../routes.dart';
import '../auth/auth_header.dart';
import '../auth/validators.dart';

class CustomerRegisterPage extends StatefulWidget {
  const CustomerRegisterPage({super.key});

  @override
  State<CustomerRegisterPage> createState() => _CustomerRegisterPageState();
}

class _CustomerRegisterPageState extends State<CustomerRegisterPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _auth = authFor(UserRole.customer);

  @override
  void initState() {
    super.initState();
    _auth.error.value = null;
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _password]) {
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
    });
    if (ok) Get.offAllNamed(Routes.home(UserRole.customer));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthHeader(
                    title: 'Create your account',
                    subtitle: 'Hire a verified driver whenever you would rather not drive.',
                  ),
                  const SizedBox(height: 28),
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
                    validator: (v) {
                      final s = (v ?? '').trim();
                      return s.isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s) ? null : 'Enter a valid email';
                    },
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    key: const Key('password'),
                    controller: _password,
                    label: 'Password',
                    icon: Icons.lock_rounded,
                    obscure: true,
                    textInputAction: TextInputAction.done,
                    validator: (v) => (v ?? '').length < 8 ? 'Use at least 8 characters' : null,
                  ),
                  const SizedBox(height: 16),
                  Obx(() {
                    final msg = _auth.error.value;
                    return msg == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(msg, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          );
                  }),
                  Obx(() => PrimaryButton(label: 'Create account', loading: _auth.isLoading.value, onPressed: _submit)),
                ],
              ),
            ),
          ),
        ),
      );
}
