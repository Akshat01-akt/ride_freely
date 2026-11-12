import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/core.dart';
import '../data/models.dart';
import '../data/sources.dart';

class WalletTab extends StatelessWidget {
  const WalletTab({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = Get.find<WalletController>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        FadeSlideIn(child: Text('My wallet', style: Theme.of(context).textTheme.headlineSmall)),
        const SizedBox(height: 16),
        FadeSlideIn(
          delay: const Duration(milliseconds: 80),
          child: Obx(() => _BalanceCard(balance: wallet.wallet.value.balance)),
        ),
        const SizedBox(height: 26),
        const FadeSlideIn(delay: Duration(milliseconds: 160), child: SectionHeader(title: 'Recent transactions')),
        const SizedBox(height: 12),
        Obx(() {
          final tx = wallet.wallet.value.transactions;
          if (wallet.loading.value) {
            return Column(children: [for (var i = 0; i < 3; i++) const Padding(padding: EdgeInsets.only(bottom: 10), child: ShimmerBox(height: 64, radius: 18))]);
          }
          if (tx.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_rounded,
              title: 'No transactions yet',
              body: 'Payments and top-ups will be listed here.',
            );
          }
          return Column(
            children: [
              for (var i = 0; i < tx.length; i++) FadeSlideIn(delay: Duration(milliseconds: 200 + 70 * i), child: _TransactionTile(tx: tx[i])),
            ],
          );
        }),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});

  final double balance;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.charcoal, AppColors.black, Color.lerp(AppColors.fuchsia, AppColors.black, 0.35)!],
            stops: const [0, 0.6, 1],
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: softShadow(alpha: 0.3, blur: 30, y: 16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Available balance', style: TextStyle(color: AppColors.cream.withValues(alpha: 0.75))),
            const SizedBox(height: 6),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: reduceMotion(context) ? balance : 0, end: balance),
              duration: AppMotion.success,
              curve: AppMotion.curve,
              builder: (_, v, _) => Text('₹${v.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.cream, fontSize: 38, fontWeight: FontWeight.w800, letterSpacing: -1)),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                label: 'Add money',
                icon: Icons.add_rounded,
                compact: true,
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Adding money opens with online payments in a later release.'))),
              ),
            ),
          ],
        ),
      );
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.tx});

  final WalletTransaction tx;

  @override
  Widget build(BuildContext context) {
    final credit = tx.amount > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: softShadow(alpha: 0.05, blur: 14, y: 5)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: (credit ? AppColors.charcoal : AppColors.fuchsia).withValues(alpha: 0.10), shape: BoxShape.circle),
            child: Icon(credit ? Icons.south_west_rounded : Icons.north_east_rounded, size: 20, color: credit ? AppColors.charcoal : AppColors.fuchsia),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(tx.date, style: TextStyle(fontSize: 12.5, color: AppColors.charcoal.withValues(alpha: 0.6))),
              ],
            ),
          ),
          Text('${credit ? '+' : '-'}₹${tx.amount.abs().toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w800, color: credit ? AppColors.charcoal : AppColors.fuchsia)),
        ],
      ),
    );
  }
}
