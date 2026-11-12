import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/core.dart';
import 'data/sources.dart';
import 'tabs/bookings_tab.dart';
import 'tabs/home_tab.dart';
import 'tabs/profile_tab.dart';
import 'tabs/wallet_tab.dart';

class CustomerHomeShell extends StatefulWidget {
  const CustomerHomeShell({super.key});

  @override
  State<CustomerHomeShell> createState() => _CustomerHomeShellState();
}

class _CustomerHomeShellState extends State<CustomerHomeShell> {
  // A route argument can open a specific tab (0 Home, 1 Bookings, 2 Wallet, 3 Profile).
  int _index = Get.arguments is int ? Get.arguments as int : 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.find<DriversController>().load();
      Get.find<WalletController>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      const HomeTab(),
      const BookingsTab(),
      const WalletTab(),
      ProfileTab(onSwitchTab: (i) => setState(() => _index = i)),
    ];
    return Scaffold(
      body: AnimatedGradientBackground(
        dark: false,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (kUiPreview)
                Container(
                  width: double.infinity,
                  color: AppColors.charcoal,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: const Text('UI preview: sample content', textAlign: TextAlign.center, style: TextStyle(color: AppColors.cream, fontSize: 11.5)),
                ),
              Expanded(
                child: AnimatedTabSwitcher(index: _index, builder: (i) => tabs[i]),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        index: _index,
        onChanged: (i) => setState(() => _index = i),
        items: const [
          NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
          NavItem(Icons.event_note_outlined, Icons.event_note_rounded, 'Bookings'),
          NavItem(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Wallet'),
          NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
        ],
      ),
    );
  }
}
