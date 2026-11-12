import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/core.dart';

import '../../routes.dart';

class DriverHomeShell extends StatefulWidget {
  const DriverHomeShell({super.key});

  @override
  State<DriverHomeShell> createState() => _DriverHomeShellState();
}

class _DriverHomeShellState extends State<DriverHomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final auth = authFor(UserRole.driver);
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: [
            _DashboardTab(auth: auth),
            const _EmptyTab(icon: Icons.notifications_none_rounded, title: 'No requests yet', body: 'Booking requests from nearby customers will show up here.'),
            const _EmptyTab(icon: Icons.account_balance_wallet_outlined, title: 'Nothing earned yet', body: 'Your daily, weekly and monthly totals will appear here.'),
            _ProfileTab(auth: auth),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.notifications_none_rounded), selectedIcon: Icon(Icons.notifications_rounded), label: 'Requests'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet_rounded), label: 'Earnings'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
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
  // Local only: going online is wired to the backend in the next phase.
  bool _online = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Obx(() {
      final p = widget.auth.profile;
      final first = (p['full_name'] as String? ?? '').split(' ').first;
      final approved = p['verification_status'] == 'APPROVED';
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Hello, $first', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Ready for your next booking?', style: text.bodyLarge?.copyWith(color: AppColors.beige)),
          const SizedBox(height: 20),
          if (!approved) const _VerificationBanner(),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _online ? AppColors.fuchsia : AppColors.graphite,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_online ? 'You are online' : 'You are offline',
                          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: AppColors.cream)),
                      const SizedBox(height: 4),
                      Text(
                        approved ? 'Go online to receive booking requests.' : 'Available once your documents are approved.',
                        style: text.bodyMedium?.copyWith(color: AppColors.cream.withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _online,
                  activeThumbColor: AppColors.cream,
                  onChanged: approved ? (v) => setState(() => _online = v) : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _Stat(label: 'Hourly rate', value: '₹${p['hourly_rate'] ?? '-'}')),
              const SizedBox(width: 12),
              Expanded(child: _Stat(label: 'Experience', value: '${p['experience_years'] ?? '-'} yrs')),
              const SizedBox(width: 12),
              Expanded(child: _Stat(label: 'Rating', value: '${p['rating'] ?? '-'}')),
            ],
          ),
        ],
      );
    });
  }
}

class _VerificationBanner extends StatelessWidget {
  const _VerificationBanner();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.beige,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.hourglass_top_rounded, color: AppColors.fuchsia),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Verification pending',
                      style: TextStyle(color: AppColors.black, fontWeight: FontWeight.w800)),
                  SizedBox(height: 2),
                  Text('Our team is reviewing your details. You can go online once you are approved.',
                      style: TextStyle(color: AppColors.charcoal)),
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
        decoration: BoxDecoration(color: AppColors.graphite, borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.cream)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.beige)),
          ],
        ),
      );
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: AppColors.beige),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(body, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.auth});
  final AuthController auth;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Obx(
          () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              const CircleAvatar(
                radius: 36,
                backgroundColor: AppColors.fuchsia,
                child: Icon(Icons.person_rounded, size: 38, color: AppColors.cream),
              ),
              const SizedBox(height: 14),
              Text('${auth.profile['full_name'] ?? ''}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text('${auth.profile['phone'] ?? ''}', textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text('Licence ${auth.profile['licence_number'] ?? ''}', textAlign: TextAlign.center),
              const Spacer(),
              OutlinedButton(
                onPressed: () async {
                  await auth.logout();
                  Get.offAllNamed(Routes.login(UserRole.driver));
                },
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: const Text('Log out'),
              ),
            ],
          ),
        ),
      );
}
