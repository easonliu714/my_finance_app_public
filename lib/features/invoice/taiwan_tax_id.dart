bool isTaiwanTaxIdFormat(String value) => RegExp(r'^\d{8}$').hasMatch(value);

bool hasValidTaiwanTaxIdChecksum(String value) {
  if (!isTaiwanTaxIdFormat(value)) return false;
  const weights = <int>[1, 2, 1, 2, 1, 2, 4, 1];
  var sum = 0;
  for (var index = 0; index < value.length; index += 1) {
    final product = int.parse(value[index]) * weights[index];
    sum += (product ~/ 10) + (product % 10);
  }
  if (sum % 10 == 0) return true;
  return value[6] == '7' && (sum + 1) % 10 == 0;
}
