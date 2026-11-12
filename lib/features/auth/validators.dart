/// Mirrors the server: an Indian mobile number, optionally prefixed with +91, 91 or 0.
final _indianMobile = RegExp(r'^(?:\+91|91|0)?[6-9][0-9]{9}$');

String? requiredPhone(String? v) {
  final cleaned = (v ?? '').replaceAll(RegExp(r'[\s\-]'), '');
  if (cleaned.isEmpty) return 'Enter your phone number';
  if (!_indianMobile.hasMatch(cleaned)) return 'Enter a valid 10-digit Indian mobile number';
  return null;
}
