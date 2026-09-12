String formatLocalPhoneNumber(String? value) {
  if (value == null) return '';
  var digits = value.replaceAll(RegExp(r'\D'), '');

  if (digits.startsWith('0092')) {
    digits = digits.substring(2);
  }
  if (digits.startsWith('92') && digits.length == 12) {
    return '0${digits.substring(2)}';
  }
  if (digits.startsWith('3') && digits.length == 10) {
    return '0$digits';
  }
  return digits;
}
