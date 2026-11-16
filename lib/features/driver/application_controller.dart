import 'package:get/get.dart';

import '../../core/core.dart';
import 'data/driver_api.dart';
import 'documents_controller.dart';

/// Loads the server-defined driver form and the driver's current answers, uploads documents and submits.
class ApplicationController extends GetxController {
  ApplicationController(this._api, this._picker, this._auth);

  final DriverApi _api;
  final DocumentPicker _picker;
  final AuthController _auth;

  final form = Rxn<FormSpec>();
  final application = Rx<DriverApplication>(const DriverApplication());
  final loading = false.obs;
  final submitting = false.obs;
  final uploading = RxnString();
  final error = RxnString();
  final fieldErrors = <String, String>{}.obs;

  /// True once a submit went through (the screen then leaves).
  final submitted = false.obs;

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    try {
      final results = await Future.wait([_api.applicationForm(), _api.application()]);
      form.value = results[0] as FormSpec;
      application.value = results[1] as DriverApplication;
    } on ApiException catch (e) {
      error.value = e.message;
    } finally {
      loading.value = false;
    }
  }

  Future<void> pickDocument(String key) async {
    if (uploading.value != null) return;
    uploading.value = key;
    error.value = null;
    try {
      final file = await _picker.pick();
      if (file == null) return;
      await _api.uploadDocument(type: key, bytes: file.bytes, filename: file.filename, contentType: file.contentType);
      application.value = await _api.application();
    } on ApiException catch (e) {
      error.value = e.message;
    } catch (_) {
      error.value = 'Could not read that file. Try another photo.';
    } finally {
      uploading.value = null;
    }
  }

  Future<void> submit(Map<String, String> answers) async {
    if (submitting.value) return;
    submitting.value = true;
    error.value = null;
    fieldErrors.clear();
    try {
      await _api.submitApplication(answers);
      await _auth.refreshProfile();
      submitted.value = true;
    } on ApiException catch (e) {
      fieldErrors.assignAll(e.fieldErrors);
      error.value = e.fieldErrors.isEmpty ? e.message : null;
      // A rejected submit can still have changed what the server knows (nothing does, but stay in step).
      try {
        application.value = await _api.application();
      } on ApiException {
        // The submit error is the useful one to show.
      }
    } finally {
      submitting.value = false;
    }
  }
}
