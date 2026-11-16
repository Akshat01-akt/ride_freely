import 'package:get/get.dart';

import '../../core/core.dart';

/// The customer's optional profile form: questions come from the server, nothing here blocks booking.
class ProfileFormController extends GetxController {
  ProfileFormController(this._client);

  final ApiClient _client;

  final form = Rxn<FormSpec>();
  final answers = <String, String>{}.obs;
  final loading = false.obs;
  final saving = false.obs;
  final error = RxnString();
  final fieldErrors = <String, String>{}.obs;

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    try {
      final spec = FormSpec.fromJson(await _client.getJson('/forms/customer'));
      final me = await _client.getJson('/customers/me');
      final saved = (me['profile'] as Map?)?['answers'] as Map? ?? const {};
      // Answers first: the form reads its starting values once, when it first appears.
      answers.assignAll({for (final e in saved.entries) '${e.key}': '${e.value}'});
      form.value = spec;
    } on ApiException catch (e) {
      form.value = null;
      error.value = e.message;
    } finally {
      loading.value = false;
    }
  }

  /// True when the server accepted the answers.
  Future<bool> save(Map<String, String> values) async {
    if (saving.value) return false;
    saving.value = true;
    error.value = null;
    fieldErrors.clear();
    try {
      await _client.putJson('/customers/profile', {'answers': values});
      return true;
    } on ApiException catch (e) {
      fieldErrors.assignAll(e.fieldErrors);
      error.value = e.fieldErrors.isEmpty ? e.message : null;
      return false;
    } finally {
      saving.value = false;
    }
  }
}
