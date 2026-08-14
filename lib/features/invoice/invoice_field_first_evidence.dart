class InvoiceFieldFirstEvidence {
  const InvoiceFieldFirstEvidence({
    this.invoicePeriod = '',
    this.randomCode = '',
    this.randomCodeSource = '',
  });

  final String invoicePeriod;
  final String randomCode;
  final String randomCodeSource;

  bool get hasRandomCode => randomCode.isNotEmpty;
  bool get suggestsElectronicInvoice => hasRandomCode;
  bool get hasAny => invoicePeriod.isNotEmpty || randomCode.isNotEmpty;
}

InvoiceFieldFirstEvidence parseInvoiceFieldFirstEvidence(List<String> rawLines) {
  final lines = rawLines
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  final searchable = lines.join('\n');
  final period = _parseInvoicePeriod(searchable);
  final random = _parseExplicitRandomCode(lines);
  return InvoiceFieldFirstEvidence(
    invoicePeriod: period,
    randomCode: random,
    randomCodeSource: random.isEmpty ? '' : 'explicit_random_code_label',
  );
}

String _parseInvoicePeriod(String text) {
  final normalized = text.replaceAll(RegExp(r'\s+'), '');
  final match = RegExp(
    r'(?:中華民國)?(\d{2,3})年(\d{1,2})[-~～至](\d{1,2})月(?:份)?',
  ).firstMatch(normalized);
  if (match == null) return '';
  final rocYear = int.tryParse(match.group(1)!);
  final startMonth = int.tryParse(match.group(2)!);
  final endMonth = int.tryParse(match.group(3)!);
  if (rocYear == null || rocYear < 80 || rocYear > 200) return '';
  if (startMonth == null || endMonth == null) return '';
  if (startMonth < 1 || endMonth > 12 || startMonth > endMonth) return '';
  return '$rocYear年$startMonth-$endMonth月份';
}

String _parseExplicitRandomCode(List<String> lines) {
  final inline = RegExp(
    r'隨機碼[:：.]?([0-9０-９OIl|]{4})(?![0-9０-９OIl|])',
    caseSensitive: false,
  );
  final standaloneValue = RegExp(r'^([0-9０-９OIl|]{4})$');
  for (var index = 0; index < lines.length; index += 1) {
    final compact = lines[index].replaceAll(RegExp(r'\s+'), '');
    final inlineMatch = inline.firstMatch(compact);
    if (inlineMatch != null) {
      final value = _normalizeFourDigits(inlineMatch.group(1)!);
      if (RegExp(r'^\d{4}$').hasMatch(value)) return value;
    }
    if (!RegExp(r'^隨機碼[:：.]?$', caseSensitive: false).hasMatch(compact)) {
      continue;
    }
    if (index + 1 >= lines.length) continue;
    final next = lines[index + 1].replaceAll(RegExp(r'\s+'), '');
    final nextMatch = standaloneValue.firstMatch(next);
    if (nextMatch == null) continue;
    final value = _normalizeFourDigits(nextMatch.group(1)!);
    if (RegExp(r'^\d{4}$').hasMatch(value)) return value;
  }
  return '';
}

String _normalizeFourDigits(String value) {
  const fullWidth = '０１２３４５６７８９';
  const ascii = '0123456789';
  var normalized = value
      .replaceAll(RegExp(r'[ＯｏO]'), '0')
      .replaceAll(RegExp(r'[ＩIl|]'), '1');
  for (var index = 0; index < fullWidth.length; index += 1) {
    normalized = normalized.replaceAll(fullWidth[index], ascii[index]);
  }
  return normalized.replaceAll(RegExp(r'[^0-9]'), '');
}
