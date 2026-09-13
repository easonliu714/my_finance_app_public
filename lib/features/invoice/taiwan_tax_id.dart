bool isTaiwanTaxIdFormat(String value) => RegExp(r'^\d{8}$').hasMatch(value);

bool hasValidTaiwanTaxIdChecksum(String value) {
  if (!isTaiwanTaxIdFormat(value)) return false;

  // Ministry of Finance business-number validation changed in 2023 from
  // divisibility by 10 to divisibility by 5 while preserving the same
  // eight-digit format and multiplication weights. Existing legacy numbers
  // that passed the old rule remain valid because divisibility by 10 is a
  // subset of divisibility by 5; newer allocated numbers such as 60282181
  // require the current rule.
  //
  // The seventh digit keeps the Ministry of Finance special case: when it is
  // 7, the weighted product for that digit is 28 and either admissible carry
  // interpretation must be accepted. With the current divisibility-by-5 rule,
  // that is equivalent to accepting either `sum` or `sum + 1` as divisible by
  // 5. This preserves legacy/current valid IDs such as 12345675 without
  // weakening the eight-digit format gate.
  const weights = <int>[1, 2, 1, 2, 1, 2, 4, 1];
  var sum = 0;
  for (var index = 0; index < value.length; index += 1) {
    final product = int.parse(value[index]) * weights[index];
    sum += (product ~/ 10) + (product % 10);
  }

  if (sum % 5 == 0) return true;
  return value[6] == '7' && (sum + 1) % 5 == 0;
}
