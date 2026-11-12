import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/core.dart';
import '../auth/auth_scaffold.dart';
import 'data/driver_api.dart';
import 'documents_controller.dart';

class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key});

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  final _c = Get.find<DocumentsController>();

  @override
  void initState() {
    super.initState();
    _c.error.value = null;
    // Loading changes observable state, so wait for the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _c.load());
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
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    FadeSlideIn(child: Text('Your documents', style: text.headlineMedium)),
                    const SizedBox(height: 6),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 60),
                      child: Text('Upload clear photos. Our team reviews them before you can go online.', style: text.bodyLarge?.copyWith(color: AppColors.beige)),
                    ),
                    const SizedBox(height: 10),
                    Obx(() => Text('${_c.requiredUploaded} of ${_c.requiredTotal} required documents uploaded', style: const TextStyle(color: AppColors.fuchsia, fontWeight: FontWeight.w700))),
                    Obx(() => FormError(_c.error.value)),
                    const SizedBox(height: 12),
                    Obx(() => Column(
                          children: [
                            for (var i = 0; i < documentSlots.length; i++)
                              FadeSlideIn(
                                delay: Duration(milliseconds: 100 + 60 * i),
                                child: _DocCard(slot: documentSlots[i], doc: _c.docs[documentSlots[i].type], busy: _c.uploading.value == documentSlots[i].type, onUpload: () => _c.upload(documentSlots[i].type)),
                              ),
                          ],
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  const _DocCard({required this.slot, required this.doc, required this.busy, required this.onUpload});

  final DocumentSlot slot;
  final DriverDocument? doc;
  final bool busy;
  final VoidCallback onUpload;

  ({String label, Color color}) get _status => switch (doc?.status) {
        null => (label: 'Not uploaded', color: AppColors.beige),
        DocumentStatus.pending => (label: 'Pending review', color: AppColors.fuchsia),
        DocumentStatus.approved => (label: 'Approved', color: AppColors.cream),
        DocumentStatus.rejected => (label: 'Rejected', color: AppColors.fuchsia),
      };

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final rejected = doc?.status == DocumentStatus.rejected;
    final buttonLabel = doc == null ? 'Upload' : (rejected ? 'Upload again' : 'Replace');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.graphite,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: rejected ? Border.all(color: AppColors.fuchsia, width: 1.5) : null,
        boxShadow: softShadow(alpha: 0.25, blur: 18, y: 8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(slot.title, style: const TextStyle(color: AppColors.cream, fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              if (!slot.required) const Text('Optional', style: TextStyle(color: AppColors.beige, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          StatusPill(label: status.label, color: status.color),
          if (rejected && doc?.note != null) ...[
            const SizedBox(height: 8),
            Text(doc!.note!, style: const TextStyle(color: AppColors.cream, height: 1.35)),
          ],
          if (doc?.status == DocumentStatus.approved) ...[
            const SizedBox(height: 6),
            Text('Replacing it needs a new review.', style: TextStyle(color: AppColors.beige.withValues(alpha: 0.8), fontSize: 12.5)),
          ],
          const SizedBox(height: 12),
          AppButton(
            label: buttonLabel,
            compact: true,
            loading: busy,
            icon: Icons.upload_rounded,
            style: doc == null || rejected ? AppButtonStyle.primary : AppButtonStyle.secondary,
            onPressed: onUpload,
          ),
        ],
      ),
    );
  }
}
