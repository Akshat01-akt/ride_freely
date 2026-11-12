import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/core.dart';
import '../../../routes.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key, required this.onSwitchTab});

  final ValueChanged<int> onSwitchTab;

  void _soon(BuildContext context, String what) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what is coming in a later release.')));

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to log in again to book a driver.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Log out')),
        ],
      ),
    );
    if (ok != true) return;
    await authFor(UserRole.customer).logout();
    Get.offAllNamed(Routes.login(UserRole.customer));
  }

  @override
  Widget build(BuildContext context) {
    final auth = authFor(UserRole.customer);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        FadeSlideIn(
          child: Obx(
            () => Column(
              children: [
                Hero(tag: 'profile-avatar', child: InitialsAvatar(name: '${auth.profile['full_name'] ?? ''}', size: 88, ring: true)),
                const SizedBox(height: 14),
                Text('${auth.profile['full_name'] ?? ''}', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 2),
                Text('${auth.profile['phone'] ?? ''}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        FadeSlideIn(delay: const Duration(milliseconds: 80), child: MenuTile(icon: Icons.event_note_rounded, title: 'My bookings', onTap: () => onSwitchTab(1))),
        FadeSlideIn(delay: const Duration(milliseconds: 130), child: MenuTile(icon: Icons.account_balance_wallet_rounded, title: 'Wallet & payments', onTap: () => onSwitchTab(2))),
        FadeSlideIn(delay: const Duration(milliseconds: 180), child: MenuTile(icon: Icons.location_on_rounded, title: 'Saved addresses', onTap: () => _soon(context, 'Saved addresses'))),
        FadeSlideIn(delay: const Duration(milliseconds: 230), child: MenuTile(icon: Icons.help_outline_rounded, title: 'Help & support', onTap: () => _soon(context, 'Help & support'))),
        FadeSlideIn(delay: const Duration(milliseconds: 280), child: MenuTile(icon: Icons.logout_rounded, title: 'Log out', danger: true, onTap: () => _confirmLogout(context))),
      ],
    );
  }
}
