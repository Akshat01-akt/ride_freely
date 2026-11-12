String? requiredPhone(String? v) {
  final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return 'Enter your phone number';
  if (digits.length < 10) return 'Enter a valid 10-digit phone number';
  return null;
}
