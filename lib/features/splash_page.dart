import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/core.dart';
import '../routes.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduce = reduceMotion(context);
    reduce ? _intro.value = 1 : _intro.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _route(reduce));
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Future<void> _route(bool reduce) async {
    try {
      // Hold the splash briefly so the intro animation can be seen.
      final hold = reduce ? Future<void>.value() : Future<void>.delayed(const Duration(milliseconds: 1700));
      final next = await _decideRoute();
      await hold;
      Get.offAllNamed(next);
    } catch (_) {
      Get.offAllNamed(Routes.role);
    }
  }

  Future<String> _decideRoute() async {
    final role = await Get.find<RoleStore>().read();
    if (role == null) {
      final seen = await Get.find<OnboardingStore>().isDone();
      return seen ? Routes.role : Routes.onboarding;
    }
    final auth = authFor(role);
    await auth.bootstrap();
    return auth.status.value == AuthStatus.authenticated ? Routes.home(role) : Routes.login(role);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: AnimatedGradientBackground(
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),
                AnimatedBuilder(
                  animation: _intro,
                  builder: (_, _) {
                    final pop = Curves.easeOutBack.transform((_intro.value / 0.6).clamp(0.0, 1.0));
                    final fade = Curves.easeOut.transform((_intro.value / 0.4).clamp(0.0, 1.0));
                    final text = Curves.easeOut.transform(((_intro.value - 0.5) / 0.5).clamp(0.0, 1.0));
                    return Column(
                      children: [
                        Opacity(
                          opacity: fade,
                          child: Transform.scale(
                            scale: 0.6 + 0.4 * pop,
                            child: BrandLogo(size: 96, onDark: true, turns: (1 - Curves.easeOutCubic.transform(_intro.value)) * 0.75),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Opacity(
                          opacity: text,
                          child: Transform.translate(
                            offset: Offset(0, 12 * (1 - text)),
                            child: const Text(
                              'Rent a Driver,\nTravel Stress-Free',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.cream, fontSize: 18, height: 1.4, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const Spacer(flex: 3),
                AnimatedBuilder(
                  animation: _intro,
                  builder: (_, _) => Container(
                    width: 64,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 40),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(color: AppColors.cream.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)),
                    child: FractionallySizedBox(
                      widthFactor: _intro.value,
                      child: Container(decoration: BoxDecoration(color: AppColors.fuchsia, borderRadius: BorderRadius.circular(2))),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
