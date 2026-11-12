import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/core.dart';
import '../../routes.dart';

class _Slide {
  const _Slide(this.title, this.body, this.art);
  final String title;
  final String body;
  final Widget Function() art;
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  double _page = 0;

  static final _slides = <_Slide>[
    _Slide('Professional drivers\nat your service', 'Safe, verified and experienced drivers for every journey.', _carArt),
    _Slide('Book by the hour\nor for the full day', 'Pick the time you need. We match you with the nearest available driver.', _timeArt),
    _Slide('Know when your\ndriver arrives', 'Follow your driver on the map once your booking is confirmed.', _routeArt),
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() => _page = _controller.page ?? 0));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await Get.find<OnboardingStore>().markDone();
    Get.offAllNamed(Routes.role);
  }

  void _next() {
    if (_page.round() >= _slides.length - 1) {
      _finish();
    } else {
      _controller.nextPage(duration: AppMotion.page, curve: AppMotion.curve);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _page.round() == _slides.length - 1;
    return Scaffold(
      body: AnimatedGradientBackground(
        dark: false,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: AnimatedOpacity(
                  duration: AppMotion.hover,
                  opacity: last ? 0 : 1,
                  child: TextButton(onPressed: last ? null : _finish, child: const Text('Skip')),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _slides.length,
                  itemBuilder: (context, i) {
                    final offset = (i - _page);
                    final s = _slides[i];
                    return LayoutBuilder(
                      builder: (context, box) {
                        // Size the illustration to the space left so small phones never overflow.
                        final stage = (box.maxHeight * 0.42).clamp(120.0, 300.0);
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Illustration drifts faster than the text for a parallax feel.
                              Transform.translate(offset: Offset(offset * 90, 0), child: SizedBox(height: stage, width: stage, child: FittedBox(child: s.art()))),
                              SizedBox(height: box.maxHeight < 420 ? 12 : 28),
                              Opacity(
                                opacity: (1 - offset.abs()).clamp(0.0, 1.0),
                                child: Column(
                                  children: [
                                    Text(s.title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: box.maxHeight < 420 ? 22 : null)),
                                    const SizedBox(height: 10),
                                    Text(s.body, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _slides.length; i++)
                    AnimatedContainer(
                      duration: AppMotion.hover,
                      curve: AppMotion.curve,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 8,
                      width: i == _page.round() ? 26 : 8,
                      decoration: BoxDecoration(
                        color: i == _page.round() ? AppColors.fuchsia : AppColors.beige,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                child: AppButton(label: last ? 'Get started' : 'Next', icon: Icons.arrow_forward_rounded, onPressed: _next),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _stage(Widget child) => Container(
        width: 300,
        height: 300,
        alignment: Alignment.center,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x55DDD0C8)),
        child: child,
      );

  static Widget _chip(IconData icon, {double size = 26}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.cream, shape: BoxShape.circle, boxShadow: softShadow(alpha: 0.12)),
        child: Icon(icon, color: AppColors.fuchsia, size: size),
      );

  static Widget _carArt() => _stage(
        Stack(
          alignment: Alignment.center,
          children: [
            const CarIllustration(width: 250, body: AppColors.charcoal, glass: AppColors.cream),
            Positioned(top: 40, right: 36, child: _chip(Icons.place_rounded)),
            Positioned(top: 70, left: 28, child: _chip(Icons.verified_user_rounded, size: 22)),
          ],
        ),
      );

  static Widget _timeArt() => _stage(
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: AppGradients.fuchsia, boxShadow: softShadow(color: AppColors.fuchsia, alpha: 0.3, blur: 30, y: 14)),
              child: const Icon(Icons.schedule_rounded, color: AppColors.cream, size: 92),
            ),
            Positioned(top: 34, left: 34, child: _chip(Icons.wb_sunny_rounded)),
            Positioned(bottom: 40, right: 30, child: _chip(Icons.nights_stay_rounded)),
          ],
        ),
      );

  static Widget _routeArt() => _stage(
        ClipOval(
          child: SizedBox(
            width: 300,
            height: 300,
            child: Stack(
              children: [
                const MapBackdrop(route: [Offset(0.22, 0.78), Offset(0.22, 0.5), Offset(0.62, 0.5), Offset(0.62, 0.24)]),
                Positioned(left: 0.62 * 300 - 18, top: 0.24 * 300 - 38, child: const Icon(Icons.place_rounded, color: AppColors.fuchsia, size: 40)),
                Positioned(left: 0.22 * 300 - 18, top: 0.78 * 300 - 18, child: _chip(Icons.directions_car_rounded, size: 20)),
              ],
            ),
          ),
        ),
      );
}
