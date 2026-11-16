import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../auth/auth_scaffold.dart';

/// What the form shows for one document slot.
class DocumentState {
  const DocumentState({required this.status, this.note});

  /// PENDING, APPROVED or REJECTED, as the server says.
  final String status;
  final String? note;
}

final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// DateTime.tryParse rolls 1990-02-30 over to March, so check that the date survives a round trip.
bool _isRealDate(String v) {
  if (!_isoDate.hasMatch(v)) return false;
  final d = DateTime.tryParse(v);
  return d != null && d.toIso8601String().startsWith(v);
}

/// Renders a server-defined form. [flagged] switches it to "fix these items" mode: only those stay editable.
class DynamicForm extends StatefulWidget {
  const DynamicForm({
    super.key,
    required this.spec,
    required this.onSubmit,
    this.initial = const {},
    this.flagged = const {},
    this.alsoEditable = const {},
    this.notes = const {},
    this.documents = const {},
    this.onPickDocument,
    this.uploading,
    this.busy = false,
    this.serverErrors = const {},
    this.submitLabel = 'Submit',
  });

  final FormSpec spec;
  final Map<String, String> initial;
  final Set<String> flagged;

  /// Questions that are also open while fixing flagged items (for example ones the admin added later).
  final Set<String> alsoEditable;

  /// Reviewer notes by field key, shown on flagged items.
  final Map<String, String> notes;
  final Map<String, DocumentState> documents;
  final void Function(String key)? onPickDocument;
  final String? uploading;
  final bool busy;
  final Map<String, String> serverErrors;
  final String submitLabel;
  final Future<void> Function(Map<String, String> answers) onSubmit;

  @override
  State<DynamicForm> createState() => _DynamicFormState();
}

class _DynamicFormState extends State<DynamicForm> {
  final _form = GlobalKey<FormState>();
  final _values = <String, String>{};
  final _controllers = <String, TextEditingController>{};

  bool get _fixing => widget.flagged.isNotEmpty;
  bool _editable(FormFieldSpec f) => !_fixing || widget.flagged.contains(f.key) || widget.alsoEditable.contains(f.key);

  @override
  void initState() {
    super.initState();
    _values.addAll(widget.initial);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(String key) =>
      _controllers.putIfAbsent(key, () => TextEditingController(text: _values[key] ?? ''));

  String? _validate(FormFieldSpec f, String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return f.required ? 'This is required' : null;
    switch (f.type) {
      case FieldType.number:
        final n = num.tryParse(v);
        return n == null || n < 0 ? 'Enter a number' : null;
      case FieldType.date:
        return _isRealDate(v) ? null : 'Use the format YYYY-MM-DD';
      case FieldType.choice:
        return f.choices.contains(v) ? null : 'Pick an option';
      default:
        return null;
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final answers = <String, String>{
      for (final f in widget.spec.visible)
        if (f.type != FieldType.document && _editable(f) && (_values[f.key] ?? '').trim().isNotEmpty) f.key: _values[f.key]!.trim(),
    };
    await widget.onSubmit(answers);
  }

  String _labelOf(String key) {
    for (final f in widget.spec.fields) {
      if (f.key == key) return f.label;
    }
    return key;
  }

  Widget _readOnly(FormFieldSpec f) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f.label, style: const TextStyle(color: AppColors.beige, fontSize: 12.5)),
            const SizedBox(height: 2),
            Text(_values[f.key] ?? '-', style: const TextStyle(color: AppColors.cream, fontSize: 16)),
          ],
        ),
      );

  Widget _note(FormFieldSpec f) {
    final note = widget.notes[f.key];
    if (!widget.flagged.contains(f.key)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text('Needs changes${note == null || note.isEmpty ? '' : ': $note'}', style: const TextStyle(color: AppColors.fuchsia, fontWeight: FontWeight.w700)),
    );
  }

  Widget _field(FormFieldSpec f) {
    if (f.type == FieldType.document) return _document(f);
    if (!_editable(f)) return _readOnly(f);
    final label = f.required ? f.label : '${f.label} (optional)';
    Widget input;
    if (f.type == FieldType.choice) {
      input = DropdownButtonFormField<String>(
        key: Key('field_${f.key}'),
        initialValue: f.choices.contains(_values[f.key]) ? _values[f.key] : null,
        decoration: InputDecoration(labelText: label),
        items: [for (final c in f.choices) DropdownMenuItem(value: c, child: Text(c))],
        onChanged: (v) => _values[f.key] = v ?? '',
        validator: (v) => _validate(f, v),
      );
    } else {
      input = AppTextField(
        key: Key('field_${f.key}'),
        controller: _controller(f.key),
        label: label,
        hint: f.type == FieldType.date ? 'YYYY-MM-DD' : f.helpText,
        keyboardType: f.type == FieldType.number
            ? const TextInputType.numberWithOptions(decimal: true)
            : f.type == FieldType.date
                ? TextInputType.datetime
                : TextInputType.text,
        onChanged: (v) => _values[f.key] = v,
        validator: (v) => _validate(f, v),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_note(f), input]),
    );
  }

  Widget _document(FormFieldSpec f) {
    final doc = widget.documents[f.key];
    final rejected = doc?.status == 'REJECTED';
    final canUpload = !_fixing || widget.flagged.contains(f.key) || doc == null;
    final label = switch (doc?.status) {
      null => 'Not uploaded',
      'APPROVED' => 'Approved',
      'REJECTED' => 'Rejected',
      _ => 'Uploaded, pending review',
    };
    return Container(
      key: Key('doc_${f.key}'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.graphite,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: rejected ? Border.all(color: AppColors.fuchsia, width: 1.5) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(f.required ? f.label : '${f.label} (optional)', style: const TextStyle(color: AppColors.cream, fontSize: 16, fontWeight: FontWeight.w800)),
          if (f.helpText != null) Text(f.helpText!, style: const TextStyle(color: AppColors.beige, fontSize: 12.5)),
          const SizedBox(height: 8),
          StatusPill(label: label, color: doc == null || rejected ? AppColors.fuchsia : AppColors.cream),
          if (rejected && (doc?.note ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(doc!.note!, style: const TextStyle(color: AppColors.cream))),
          if (canUpload && widget.onPickDocument != null) ...[
            const SizedBox(height: 10),
            AppButton(
              label: doc == null ? 'Upload' : (rejected ? 'Upload again' : 'Replace'),
              compact: true,
              icon: Icons.upload_rounded,
              loading: widget.uploading == f.key,
              style: doc == null || rejected ? AppButtonStyle.primary : AppButtonStyle.secondary,
              onPressed: () => widget.onPickDocument!(f.key),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.spec.needsNewerApp) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('This form has new questions this version of the app cannot show. Update the app to continue.', style: TextStyle(color: AppColors.cream, fontSize: 16, height: 1.4)),
      );
    }
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final f in widget.spec.visible) _field(f),
          for (final e in widget.serverErrors.entries) FormError('${_labelOf(e.key)}: ${e.value}'),
          const SizedBox(height: 8),
          AppButton(label: widget.submitLabel, loading: widget.busy, onPressed: _submit),
        ],
      ),
    );
  }
}
