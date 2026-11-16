import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/core.dart';
import '../../routes.dart';
import 'auth_scaffold.dart';
import 'server_help.dart';
import 'validators.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.role});

  final UserRole role;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  late final _auth = authFor(widget.role);

  bool get _driver => widget.role == UserRole.driver;

  @override
  void initState() {
    super.initState();
    _auth.error.value = null;
  }

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (await _auth.login(_identifier.text.trim(), _password.text)) {
      Get.offAllNamed(Routes.home(widget.role));
    }
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
    title: 'Welcome back 👋',
    subtitle: _driver
        ? 'Drive more. Earn on your terms. Log in to continue.'
        : 'Your car. Our driver. Log in to continue.',
    footer: [
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(_driver ? 'Want to drive with us?' : 'New here?'),
          HoverLink(
            label: _driver ? 'Register as a driver' : 'Create an account',
            onTap: () => Get.toNamed(Routes.register(widget.role)),
          ),
        ],
      ),
      Center(
        child: HoverLink(
          label: 'Switch account type',
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          onTap: () async {
            await Get.find<RoleStore>().clear();
            Get.offAllNamed(Routes.role);
          },
        ),
      ),
    ],
    children: [
      Form(
        key: _form,
        child: Column(
          children: [
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
              label: 'Password',
              icon: Icons.lock_rounded,
              obscure: true,
              textInputAction: TextInputAction.done,
              validator: (v) =>
                  (v ?? '').isEmpty ? 'Enter your password' : null,
            ),
          ],
        ),
      ),
      Obx(() => FormError(_auth.error.value)),
      ServerHelp(auth: _auth),
      const SizedBox(height: 16),
      Obx(
        () => AppButton(
          label: 'Log in',
          loading: _auth.isLoading.value,
          onPressed: _submit,
        ),
      ),
    ],
  );
}
