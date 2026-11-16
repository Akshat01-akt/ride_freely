/// The kinds of field the server can ask for. Anything this app does not know becomes [unknown].
enum FieldType { text, number, date, choice, document, unknown }

FieldType _typeOf(String? name) => FieldType.values.firstWhere(
      (t) => t.name == name && t != FieldType.unknown,
      orElse: () => FieldType.unknown,
    );

class FormFieldSpec {
  const FormFieldSpec({
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    this.helpText,
    this.choices = const [],
  });

  factory FormFieldSpec.fromJson(Map<String, dynamic> j) => FormFieldSpec(
        key: j['key'] as String,
        label: j['label'] as String,
        type: _typeOf(j['field_type'] as String?),
        required: j['required'] == true,
        helpText: j['help_text'] as String?,
        choices: ((j['choices'] as List?) ?? const []).cast<String>(),
      );

  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final String? helpText;
  final List<String> choices;
}

class FormSpec {
  const FormSpec({required this.version, required this.fields});

  factory FormSpec.fromJson(Map<String, dynamic> j) => FormSpec(
        version: (j['version'] as num).toInt(),
        fields: (j['fields'] as List).cast<Map<String, dynamic>>().map(FormFieldSpec.fromJson).toList(),
      );

  final int version;
  final List<FormFieldSpec> fields;

  /// A required field this app cannot show: submitting would always be refused, so the app asks for an update instead.
  bool get needsNewerApp => fields.any((f) => f.required && f.type == FieldType.unknown);

  /// What the app can show; unknown optional fields are skipped.
  List<FormFieldSpec> get visible => fields.where((f) => f.type != FieldType.unknown).toList();
}
