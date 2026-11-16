import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/core.dart';
import '../auth/auth_scaffold.dart';
import '../forms/dynamic_form.dart';
import 'profile_form_controller.dart';

/// "Complete your profile": optional, never blocks booking.
class ProfileFormPage extends StatefulWidget {
  const ProfileFormPage({super.key});

  @override
  State<ProfileFormPage> createState() => _ProfileFormPageState();
}

class _ProfileFormPageState extends State<ProfileFormPage> {
  final _auth = authFor(UserRole.customer);
  late final ProfileFormController _c = Get.put(ProfileFormController(_auth.client));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _c.load());
  }

  @override
  void dispose() {
    Get.delete<ProfileFormController>();
    super.dispose();
  }

  Future<void> _save(Map<String, String> values) async {
    if (!await _c.save(values)) return;
    await _auth.refreshProfile();
    Get.back();
    Get.snackbar('Saved', 'Your profile is up to date.', snackPosition: SnackPosition.BOTTOM);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: AnimatedGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(tooltip: 'Back', onPressed: Get.back, icon: const Icon(Icons.arrow_back_rounded)),
              ),
              Expanded(
                child: Obx(() {
                  final spec = _c.form.value;
                  if (spec == null) {
                    return _c.loading.value
                        ? const Center(child: CircularProgressIndicator())
                        : Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                FormError(_c.error.value ?? 'Could not load the form.'),
                                const SizedBox(height: 12),
                                AppButton(label: 'Try again', compact: true, onPressed: _c.load),
                              ]),
                            ),
                          );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    children: [
                      Text('Complete your profile', style: text.headlineMedium),
                      const SizedBox(height: 6),
                      Text('Optional. It helps drivers find you faster.', style: text.bodyLarge?.copyWith(color: AppColors.beige)),
                      Obx(() => FormError(_c.error.value)),
                      const SizedBox(height: 16),
                      DynamicForm(
                        key: ValueKey(spec.version),
                        spec: spec,
                        initial: Map.of(_c.answers),
                        busy: _c.saving.value,
                        serverErrors: Map.of(_c.fieldErrors),
                        submitLabel: 'Save',
                        onSubmit: _save,
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
}
