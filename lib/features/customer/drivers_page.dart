import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/core.dart';
import '../../routes.dart';
import 'data/models.dart';
import 'data/sources.dart';
import 'widgets/driver_card.dart';
import 'widgets/drivers_error.dart';

enum _Filter { all, verified, topRated, lowestPrice }

class DriversPage extends StatefulWidget {
  const DriversPage({super.key});

  @override
  State<DriversPage> createState() => _DriversPageState();
}

class _DriversPageState extends State<DriversPage> {
  final _drivers = Get.find<DriversController>();
  final _query = TextEditingController();
  _Filter _filter = _Filter.all;

  /// Which quick service opened this screen (shown as a label; matching by mode comes with bookings).
  String? get _mode => Get.arguments is String ? Get.arguments as String : null;

  @override
  void initState() {
    super.initState();
    // Loading changes observable state, so wait until the first frame has been built.
    WidgetsBinding.instance.addPostFrameCallback((_) => _drivers.load());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<DriverSummary> get _visible {
    var list = _drivers.drivers.where((d) => d.name.toLowerCase().contains(_query.text.trim().toLowerCase())).toList();
    switch (_filter) {
      case _Filter.all:
        break;
      case _Filter.verified:
        list = list.where((d) => d.verified).toList();
      case _Filter.topRated:
        list.sort((a, b) => b.rating.compareTo(a.rating));
      case _Filter.lowestPrice:
        list.sort((a, b) => a.hourlyRate.compareTo(b.hourlyRate));
    }
    return list;
  }

  static String _label(_Filter f) => switch (f) {
        _Filter.all => 'All',
        _Filter.verified => 'Verified',
        _Filter.topRated => 'Top rated',
        _Filter.lowestPrice => 'Lowest price',
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        body: AnimatedGradientBackground(
          dark: false,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 20, 0),
                  child: Row(
                    children: [
                      IconButton(tooltip: 'Back', onPressed: Get.back, icon: const Icon(Icons.arrow_back_rounded)),
                      Expanded(child: Text('Available drivers', style: Theme.of(context).textTheme.titleLarge)),
                      if (_mode != null) StatusPill(label: _mode!, color: AppColors.fuchsia),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: TextField(
                    controller: _query,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(hintText: 'Search by name', prefixIcon: Icon(Icons.search_rounded)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      for (final f in _Filter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Pressable(
                            onTap: () => setState(() => _filter = f),
                            child: AnimatedContainer(
                              duration: AppMotion.hover,
                              curve: AppMotion.curve,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 18),
                              decoration: BoxDecoration(
                                color: _filter == f ? AppColors.fuchsia : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: _filter == f ? softShadow(color: AppColors.fuchsia, alpha: 0.3, blur: 12, y: 5) : softShadow(alpha: 0.05, blur: 8, y: 3),
                              ),
                              child: Text(_label(f), style: TextStyle(fontWeight: FontWeight.w700, color: _filter == f ? AppColors.cream : AppColors.charcoal)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Obx(() {
                    if (_drivers.loading.value) {
                      return ListView(padding: const EdgeInsets.symmetric(horizontal: 20), children: [for (var i = 0; i < 4; i++) const Padding(padding: EdgeInsets.only(bottom: 12), child: ShimmerBox(height: 92, radius: 24))]);
                    }
                    if (_drivers.error.value != null) return DriversError(controller: _drivers);
                    final list = _visible;
                    if (list.isEmpty) {
                      final searching = _query.text.isNotEmpty || _filter != _Filter.all;
                      return EmptyState(
                        icon: Icons.person_search_rounded,
                        title: searching ? 'No drivers match' : 'No drivers nearby yet',
                        body: searching ? 'Try a different name or clear the filter.' : 'Verified drivers who are online will show up here.',
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        for (var i = 0; i < list.length; i++)
                          FadeSlideIn(
                            key: ValueKey('${_filter.name}-${list[i].id}'),
                            delay: Duration(milliseconds: 60 * i),
                            child: DriverCard(driver: list[i], onTap: () => Get.toNamed(Routes.driverDetails, arguments: list[i])),
                          ),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      );
}
