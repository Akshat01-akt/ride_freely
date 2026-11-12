import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/core.dart';
import '../../routes.dart';
import '../auth/auth_scaffold.dart';
import '../bookings/bookings.dart';
import 'availability_controller.dart';
import 'requests_tab.dart';

class DriverHomeShell extends StatefulWidget {
  const DriverHomeShell({super.key});

  @override
  State<DriverHomeShell> createState() => _DriverHomeShellState();
}

class _DriverHomeShellState extends State<DriverHomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => bookingsFor(UserRole.driver).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = authFor(UserRole.driver);
    final tabs = <Widget>[
      _DashboardTab(auth: auth),
      const RequestsTab(),
      const EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Nothing earned yet',
        body: 'Your daily, weekly and monthly totals will appear here.',
      ),
      _ProfileTab(auth: auth),
    ];
    return Scaffold(
      body: AnimatedGradientBackground(
        child: FloatingIconsBackground(
          dark: true,
          child: SafeArea(
            bottom: false,
            child: AnimatedTabSwitcher(index: _index, builder: (i) => tabs[i]),
          ),
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        index: _index,
        onChanged: (i) {
          setState(() => _index = i);
          if (i == 1) {
            bookingsFor(UserRole.driver).load(keepItems: true);
          }
        },
        items: const [
          NavItem(
            Icons.dashboard_outlined,
            Icons.dashboard_rounded,
            'Dashboard',
          ),
          NavItem(
            Icons.notifications_none_rounded,
            Icons.notifications_rounded,
            'Requests',
          ),
          NavItem(
            Icons.account_balance_wallet_outlined,
            Icons.account_balance_wallet_rounded,
            'Earnings',
          ),
          NavItem(
            Icons.person_outline_rounded,
            Icons.person_rounded,
            'Profile',
          ),
        ],
      ),
    );
  }
}

class _DashboardTab extends StatefulWidget {
  const _DashboardTab({required this.auth});

  final AuthController auth;

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  final _availability = Get.find<AvailabilityController>();

  @override
  void initState() {
    super.initState();
    // If the server still has this driver AVAILABLE (app was restarted), keep sharing the position.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _availability.resumeIfAvailable(
        '${widget.auth.profile['availability_status']}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Obx(() {
      final p = widget.auth.profile;
      final name = '${p['full_name'] ?? ''}';
      final approved = p['verification_status'] == 'APPROVED';
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          FadeSlideIn(child: DayPartCard(name: name)),
          const SizedBox(height: 20),
          if (!approved)
            FadeSlideIn(
              delay: const Duration(milliseconds: 60),
              child: _VerificationBanner(
                onUpload: () => Get.toNamed(Routes.documents),
              ),
            ),
          FadeSlideIn(
            delay: const Duration(milliseconds: 120),
            child: Obx(() {
              final online = _availability.online.value;
              return AnimatedContainer(
                duration: AppMotion.page,
                curve: AppMotion.curve,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: online ? AppGradients.fuchsia : null,
                  color: online ? null : AppColors.graphite,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: online
                      ? softShadow(
                          color: AppColors.fuchsia,
                          alpha: 0.35,
                          blur: 28,
                          y: 14,
                        )
                      : softShadow(alpha: 0.3),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedSwitcher(
                            duration: AppMotion.tap,
                            child: Text(
                              online ? 'You are online' : 'You are offline',
                              key: ValueKey(online),
                              style: text.titleLarge,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            online
                                ? 'Customers nearby can see you. Keep the app open to stay visible.'
                                : approved
                                ? 'Go online to receive booking requests.'
                                : 'Available once your documents are approved.',
                            style: TextStyle(
                              color: AppColors.cream.withValues(alpha: 0.8),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_availability.busy.value)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    else
                      Switch(
                        value: online,
                        activeThumbColor: AppColors.cream,
                        onChanged: approved ? _availability.setOnline : null,
                      ),
                  ],
                ),
              );
            }),
          ),
          Obx(() => FormError(_availability.error.value)),
          Obx(() {
            final w = _availability.warning.value;
            return w == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      w,
                      style: const TextStyle(color: AppColors.beige),
                    ),
                  );
          }),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FadeSlideIn(
                  delay: const Duration(milliseconds: 180),
                  child: _Stat(
                    label: 'Hourly rate',
                    value: '₹${p['hourly_rate'] ?? '-'}',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FadeSlideIn(
                  delay: const Duration(milliseconds: 240),
                  child: _Stat(
                    label: 'Experience',
                    value: '${p['experience_years'] ?? '-'} yrs',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FadeSlideIn(
                  delay: const Duration(milliseconds: 300),
                  child: _Stat(label: 'Rating', value: '${p['rating'] ?? '-'}'),
                ),
              ),
            ],
          ),
        ],
      );
    });
  }
}

class _VerificationBanner extends StatelessWidget {
  const _VerificationBanner({required this.onUpload});

  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.beige,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.hourglass_top_rounded, color: AppColors.fuchsia),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Verification pending',
                style: TextStyle(
                  color: AppColors.black,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Upload your licence and ID proof. You can go online once our team approves them.',
                style: TextStyle(color: AppColors.charcoal, height: 1.35),
              ),
              const SizedBox(height: 10),
              AppButton(
                label: 'Upload documents',
                compact: true,
                icon: Icons.upload_file_rounded,
                onPressed: onUpload,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.graphite,
      borderRadius: BorderRadius.circular(AppRadius.md),
      boxShadow: softShadow(alpha: 0.25, blur: 16, y: 8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.cream,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.beige),
        ),
      ],
    ),
  );
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.auth});

  final AuthController auth;

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will stop receiving booking requests.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // Stop sharing immediately, then tell the server while the session is still valid.
    final availability = Get.find<AvailabilityController>();
    availability.forceOffline();
    await availability.setOnline(false);
    await auth.logout();
    Get.offAllNamed(Routes.login(UserRole.driver));
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
    children: [
      FadeSlideIn(
        child: Obx(
          () => Column(
            children: [
              InitialsAvatar(
                name: '${auth.profile['full_name'] ?? ''}',
                size: 88,
                ring: true,
              ),
              const SizedBox(height: 14),
              Text(
                '${auth.profile['full_name'] ?? ''}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text('${auth.profile['phone'] ?? ''}'),
              const SizedBox(height: 2),
              Text('Licence ${auth.profile['licence_number'] ?? ''}'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      FadeSlideIn(
        delay: const Duration(milliseconds: 100),
        child: MenuTile(
          icon: Icons.logout_rounded,
          title: 'Log out',
          danger: true,
          onTap: () => _confirmLogout(context),
        ),
      ),
    ],
  );
}
