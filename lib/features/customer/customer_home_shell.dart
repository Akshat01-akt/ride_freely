import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/core.dart';

import '../../routes.dart';

class CustomerHomeShell extends StatefulWidget {
  const CustomerHomeShell({super.key});

  @override
  State<CustomerHomeShell> createState() => _CustomerHomeShellState();
}

class _CustomerHomeShellState extends State<CustomerHomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final auth = authFor(UserRole.customer);
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: [
            _HomeTab(auth: auth),
            const _BookingsTab(),
            _ProfileTab(auth: auth),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note_rounded), label: 'Bookings'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.auth});
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Obx(() {
          final first = (auth.profile['full_name'] as String? ?? '').split(' ').first;
          return Text('Hello, $first', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800));
        }),
        const SizedBox(height: 4),
        Text('Where do you need a driver today?', style: text.bodyLarge),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: AppColors.charcoal, borderRadius: BorderRadius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your car. Our driver.',
                  style: text.titleLarge?.copyWith(color: AppColors.cream, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('A verified driver, by the hour or for the full day.',
                  style: text.bodyMedium?.copyWith(color: AppColors.beige)),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Book a driver',
                onPressed: () => ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Booking opens in the next release'))),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Text('Pick a duration', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final d in ['2 hours', '4 hours', '8 hours', 'Full day'])
              Chip(
                label: Text(d),
                backgroundColor: AppColors.beige,
                side: BorderSide.none,
                labelStyle: const TextStyle(color: AppColors.charcoal, fontWeight: FontWeight.w600),
              ),
          ],
        ),
        const SizedBox(height: 28),
        Text('How it works', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        const _Step(icon: Icons.place_rounded, title: 'Set your pickup', body: 'Tell us where and when you need a driver.'),
        const _Step(icon: Icons.verified_user_rounded, title: 'Get matched', body: 'We send your request to the nearest verified driver.'),
        const _Step(icon: Icons.key_rounded, title: 'Sit back', body: 'Your driver takes the wheel of your own car.'),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.fuchsia.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: AppColors.fuchsia),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      );
}

class _BookingsTab extends StatelessWidget {
  const _BookingsTab();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_busy_rounded, size: 56, color: AppColors.beige),
              SizedBox(height: 12),
              Text('No bookings yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              SizedBox(height: 4),
              Text('Your upcoming and past bookings will appear here.', textAlign: TextAlign.center),
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
              const Spacer(),
              OutlinedButton(
                onPressed: () async {
                  await auth.logout();
                  Get.offAllNamed(Routes.login(UserRole.customer));
                },
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: const Text('Log out'),
              ),
            ],
          ),
        ),
      );
}
