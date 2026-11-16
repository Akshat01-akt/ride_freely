/// Mirrors the server: an Indian mobile number, optionally prefixed with +91, 91 or 0.
final _indianMobile = RegExp(r'^(?:\+91|91|0)?[6-9][0-9]{9}$');

String? requiredPhone(String? v) {
  final cleaned = (v ?? '').replaceAll(RegExp(r'[\s\-]'), '');
  if (cleaned.isEmpty) return 'Enter your phone number';
  if (!_indianMobile.hasMatch(cleaned)) return 'Enter a valid 10-digit Indian mobile number';
  return null;
}

String? optionalEmail(String? v) {
  final s = (v ?? '').trim();
  return s.isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s) ? null : 'Enter a valid email';
}

/// One field for either: an email address (has "@") or an Indian mobile number.
String? requiredIdentifier(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return 'Enter your email or mobile number';
  if (s.contains('@')) return optionalEmail(s) == null ? null : 'Enter a valid email address';
  return requiredPhone(s) == null ? null : 'Enter a valid email or 10-digit mobile number';
}

/// The registration fields the server expects for what was typed in the identifier box.
Map<String, String> identifierFields(String identifier) {
  final s = identifier.trim();
  return s.contains('@') ? {'email': s} : {'phone': s};
}
