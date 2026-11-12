import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/core.dart';
import 'data/driver_api.dart';

class EarningsController extends GetxController {
  EarningsController(this._api);

  final DriverApi _api;
  final data = Rxn<Earnings>();
  final loading = false.obs;
  final error = RxnString();

  /// A plain load clears the previous driver's totals first; a refresh ([keep]) leaves them showing.
  Future<void> load({bool keep = false}) async {
    loading.value = true;
    error.value = null;
    if (!keep) data.value = null;
    try {
      data.value = await _api.earnings();
    } catch (e) {
      data.value = null;
      error.value = e is ApiException ? e.message : 'Something went wrong. Please try again.';
    } finally {
      loading.value = false;
    }
  }
}

class EarningsTab extends StatelessWidget {
  const EarningsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<EarningsController>();
    final text = Theme.of(context).textTheme;
    return Obx(() {
      final e = c.data.value;
      if (c.error.value != null) {
        return EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load earnings',
          body: c.error.value!,
          action: AppButton(label: 'Try again', compact: true, onPressed: c.load),
        );
      }
      if (e == null) {
        return ListView(padding: const EdgeInsets.all(20), children: [for (var i = 0; i < 2; i++) const Padding(padding: EdgeInsets.only(bottom: 12), child: ShimmerBox(height: 90, radius: 24))]);
      }
      return RefreshIndicator(
        onRefresh: () => c.load(keep: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            FadeSlideIn(child: Text('Earnings', style: text.headlineSmall)),
            const SizedBox(height: 14),
            for (final (i, (label, p)) in [('Today', e.today), ('This week', e.week), ('This month', e.month), ('All time', e.total)].indexed)
              FadeSlideIn(delay: Duration(milliseconds: 60 * i), child: _PeriodCard(label: label, period: p)),
            const SizedBox(height: 6),
            const Text('Totals are booking prices before any commission. Payouts are not part of the app yet.', style: TextStyle(fontSize: 12.5)),
          ],
        ),
      );
    });
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.label, required this.period});

  final String label;
  final EarningsPeriod period;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.graphite, borderRadius: BorderRadius.circular(AppRadius.md), boxShadow: softShadow(alpha: 0.25, blur: 16, y: 8)),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: AppColors.beige)),
              const SizedBox(height: 2),
              Text(period.trips == 1 ? '1 trip' : '${period.trips} trips', style: const TextStyle(color: AppColors.cream)),
            ],
          ),
        ),
        Text('₹${period.amount}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.cream)),
      ],
    ),
  );
}
