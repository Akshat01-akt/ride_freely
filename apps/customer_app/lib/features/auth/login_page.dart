import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ride_core/ride_core.dart';

import '../../routes.dart';
import 'auth_header.dart';
import 'validators.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _auth = Get.find<AuthController>();

  @override
  void initState() {
    super.initState();
    _auth.error.value = null;
  }

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (await _auth.login(_phone.text.trim(), _password.text)) Get.offAllNamed(Routes.home);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthHeader(
                    title: 'Your car.\nOur driver.',
                    subtitle: 'Book a trusted driver by the hour or for the full day.',
                  ),
                  const SizedBox(height: 32),
                  AppTextField(
                    key: const Key('phone'),
                    controller: _phone,
                    label: 'Phone number',
                    hint: '98765 43210',
                    icon: Icons.phone_rounded,
                    keyboardType: TextInputType.phone,
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your phone number' : requiredPhone(v),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    key: const Key('password'),
                    controller: _password,
                    label: 'Password',
                    icon: Icons.lock_rounded,
                    obscure: true,
                    textInputAction: TextInputAction.done,
                    validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
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
                  Obx(() => PrimaryButton(label: 'Log in', loading: _auth.isLoading.value, onPressed: _submit)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('New here?'),
                      TextButton(onPressed: () => Get.toNamed(Routes.register), child: const Text('Create an account')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
