import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/core.dart';
import '../../routes.dart';
import 'auth_scaffold.dart';
import 'server_help.dart';
import 'validators.dart';

/// Sign-up for both roles: a name, an email or mobile number, and a password. Details come later.
class RegisterForm extends StatefulWidget {
  const RegisterForm({super.key, required this.role, required this.title, required this.subtitle});

  final UserRole role;
  final String title;
  final String subtitle;

  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  late final _auth = authFor(widget.role);

  @override
  void initState() {
    super.initState();
    _auth.error.value = null;
  }

  @override
  void dispose() {
    for (final c in [_name, _identifier, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final ok = await _auth.register({
      'full_name': _name.text.trim(),
      ...identifierFields(_identifier.text),
      'password': _password.text,
    });
    if (ok) Get.offAllNamed(Routes.home(widget.role));
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        showBack: true,
        title: widget.title,
        subtitle: widget.subtitle,
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
                  key: const Key('identifier'),
                  controller: _identifier,
                  label: 'Email or mobile number',
                  hint: 'you@example.com or 98765 43210',
                  icon: Icons.alternate_email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  validator: requiredIdentifier,
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
