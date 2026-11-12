import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/core.dart';

/// Shown under a failed login or registration when the server could not be reached.
/// Debug builds only: a released app has a fixed address and nothing for the user to set.
class ServerHelp extends StatelessWidget {
  const ServerHelp({super.key, required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode) return const SizedBox.shrink();
    return Obx(() {
      if (!auth.connectionFailed.value) return const SizedBox.shrink();
      final address =
          auth.serverAddress.value ?? Get.find<ServerConfig>().url.value;
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'The app is trying $address. If the backend runs on your computer, use its address on your Wi-Fi, for example 192.168.0.10.',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.75),
                height: 1.4,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            AppButton(
              label: 'Change server address',
              compact: true,
              style: AppButtonStyle.secondary,
              icon: Icons.settings_ethernet_rounded,
              onPressed: () => showServerAddressDialog(context, auth),
            ),
          ],
        ),
      );
    });
  }
}

Future<void> showServerAddressDialog(
  BuildContext context,
  AuthController auth,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => const _ServerAddressDialog(),
  );
  if (saved == true) {
    auth.error.value = null;
    auth.connectionFailed.value = false;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Server address saved: ${Get.find<ServerConfig>().url.value}. Try again.',
        ),
      ),
    );
  }
}

class _ServerAddressDialog extends StatefulWidget {
  const _ServerAddressDialog();

  @override
  State<_ServerAddressDialog> createState() => _ServerAddressDialogState();
}

class _ServerAddressDialogState extends State<_ServerAddressDialog> {
  final _config = Get.find<ServerConfig>();
  late final _controller = TextEditingController(text: _config.url.value);
  String? _problem;

  @override
  void dispose() {
    _controller
        .dispose(); // owned by this State, so it outlives the closing animation
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await _config.set(_controller.text);
    } on FormatException {
      setState(
        () => _problem =
            'Enter an address like 192.168.0.10 or http://192.168.0.10:8000',
      );
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _useDefault() async {
    await _config.reset();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Server address'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Where is the DriveRent backend running?'),
        const SizedBox(height: 12),
        TextField(
          key: const Key('server_address_field'),
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: 'e.g. 192.168.0.10',
            errorText: _problem,
            errorMaxLines: 3,
          ),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: _useDefault, child: const Text('Use default')),
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      TextButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
