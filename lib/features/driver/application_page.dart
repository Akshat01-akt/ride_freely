import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/core.dart';
import '../../routes.dart';
import '../auth/auth_scaffold.dart';
import '../forms/dynamic_form.dart';
import 'application_controller.dart';
import 'data/driver_api.dart';
import 'documents_controller.dart';

/// The driver's application: details and documents, drawn from the server's form.
/// Shown in place of the dashboard until the application is submitted (or sent back for changes).
class ApplicationPage extends StatefulWidget {
  const ApplicationPage({super.key});

  @override
  State<ApplicationPage> createState() => _ApplicationPageState();
}

class _ApplicationPageState extends State<ApplicationPage> {
  late final ApplicationController _c;
  final _auth = authFor(UserRole.driver);
  Worker? _leaveOnSubmit;

  @override
  void initState() {
    super.initState();
    _c = Get.put(ApplicationController(Get.find<DriverApi>(), Get.find<DocumentPicker>(), _auth));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _c.load();
      if (!mounted) return;
      // Opened on top of the dashboard (an approved driver answering new questions): go back after submitting.
      _leaveOnSubmit = ever(_c.submitted, (done) {
        if (done == true && Navigator.of(context).canPop()) Get.back();
      });
    });
  }

  @override
  void dispose() {
    _leaveOnSubmit?.dispose();
    Get.delete<ApplicationController>();
    super.dispose();
  }

  Future<void> _logout() async {
    await _auth.logout();
    Get.offAllNamed(Routes.login(UserRole.driver));
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
                child: Navigator.of(context).canPop()
                    ? IconButton(tooltip: 'Back', onPressed: Get.back, icon: const Icon(Icons.arrow_back_rounded))
                    : TextButton.icon(onPressed: _logout, icon: const Icon(Icons.logout_rounded), label: const Text('Log out')),
              ),
              Expanded(
                child: Obx(() {
                  final spec = _c.form.value;
                  final app = _c.application.value;
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
                  final flagged = app.flagged;
                  final fixing = flagged.isNotEmpty;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    children: [
                      FadeSlideIn(child: Text(fixing ? 'Needs changes' : 'Your driver application', style: text.headlineMedium)),
                      const SizedBox(height: 6),
                      Text(
                        fixing
                            ? 'Our team asked you to fix the items below. Everything else stays as it is.'
                            : app.needsUpdate.isNotEmpty && app.status == 'APPROVED'
                                ? 'We added a few new questions. You stay bookable while you answer them.'
                                : 'Tell us about yourself and upload your documents. Our team verifies them before you appear to customers.',
                        style: text.bodyLarge?.copyWith(color: AppColors.beige),
                      ),
                      Obx(() => FormError(_c.error.value)),
                      const SizedBox(height: 16),
                      DynamicForm(
                        key: ValueKey('${spec.version}-${app.status}-${flagged.length}'),
                        spec: spec,
                        initial: {for (final e in app.answers.entries) e.key: e.value.value},
                        flagged: flagged,
                        alsoEditable: app.needsUpdate.toSet(),
                        notes: {
                          for (final e in app.answers.entries)
                            if (e.value.status == 'REJECTED' && e.value.note != null) e.key: e.value.note!,
                        },
                        documents: {
                          for (final e in app.documents.entries)
                            e.key: DocumentState(status: e.value.status.name.toUpperCase(), note: e.value.note),
                        },
                        onPickDocument: _c.pickDocument,
                        uploading: _c.uploading.value,
                        busy: _c.submitting.value,
                        serverErrors: Map.of(_c.fieldErrors),
                        submitLabel: fixing ? 'Send for review again' : 'Submit application',
                        onSubmit: _c.submit,
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
