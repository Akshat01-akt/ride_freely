import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/core.dart';
import 'data/driver_api.dart';

class PickedDocument {
  const PickedDocument({required this.bytes, required this.filename, required this.contentType});

  final List<int> bytes;
  final String filename;
  final String contentType;
}

/// Lets the driver choose a document photo. Behind an interface so tests need no gallery.
abstract class DocumentPicker {
  Future<PickedDocument?> pick();
}

class ImagePickerDocumentPicker implements DocumentPicker {
  @override
  Future<PickedDocument?> pick() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, imageQuality: 85);
    if (file == null) return null;
    final name = file.name.toLowerCase();
    final type = file.mimeType ?? (name.endsWith('.png') ? 'image/png' : 'image/jpeg');
    return PickedDocument(bytes: await file.readAsBytes(), filename: file.name, contentType: type);
  }
}

class DocumentSlot {
  const DocumentSlot(this.type, this.title, {required this.required});

  final String type;
  final String title;
  final bool required;
}

const documentSlots = [
  DocumentSlot('LICENCE', 'Driving licence', required: true),
  DocumentSlot('ID_PROOF', 'ID proof', required: true),
  DocumentSlot('PHOTO', 'Profile photo', required: false),
];

class DocumentsController extends GetxController {
  DocumentsController(this._api, this._picker);

  final DriverApi _api;
  final DocumentPicker _picker;

  final docs = <String, DriverDocument>{}.obs;
  final loading = false.obs;

  /// The type being uploaded right now, if any.
  final uploading = RxnString();
  final error = RxnString();

  int get requiredUploaded => documentSlots.where((s) => s.required && docs.containsKey(s.type)).length;
  int get requiredTotal => documentSlots.where((s) => s.required).length;

  Future<void> load() async {
    loading.value = true;
    try {
      final list = await _api.documents();
      docs.assignAll({for (final d in list) d.type: d});
    } on ApiException catch (e) {
      error.value = e.message;
    } finally {
      loading.value = false;
    }
  }

  Future<void> upload(String type) async {
    if (uploading.value != null) return;
    uploading.value = type;
    error.value = null;
    try {
      final file = await _picker.pick();
      if (file == null) return;
      await _api.uploadDocument(type: type, bytes: file.bytes, filename: file.filename, contentType: file.contentType);
      await load();
    } on ApiException catch (e) {
      error.value = e.message;
    } catch (_) {
      error.value = 'Could not read that file. Try another photo.';
    } finally {
      uploading.value = null;
    }
  }
}
