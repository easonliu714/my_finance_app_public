bool isTaiwanTaxIdFormat(String value) => RegExp(r'^\d{8}$').hasMatch(value);

bool hasValidTaiwanTaxIdChecksum(String value) {
  if (!isTaiwanTaxIdFormat(value)) return false;

  // Ministry of Finance business-number validation changed in 2023 from
  // divisibility by 10 to divisibility by 5 while preserving the same
  // eight-digit format and multiplication weights. Existing legacy numbers
  // that passed the old rule remain valid because divisibility by 10 is a
  // subset of divisibility by 5; newer allocated numbers such as 60282181
  // require the current rule.
  const weights = <int>[1, 2, 1, 2, 1, 2, 4, 1];
  var sum = 0;
  for (var index = 0; index < value.length; index += 1) {
    final product = int.parse(value[index]) * weights[index];
    sum += (product ~/ 10) + (product % 10);
  }
  return sum % 5 == 0;
}
