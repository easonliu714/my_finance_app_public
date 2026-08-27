String formatInvoicePeriodForDate(DateTime date) {
  final rocYear = date.year - 1911;
  final startMonth = date.month.isOdd ? date.month : date.month - 1;
  final endMonth = startMonth + 1;
  return '${rocYear}年${startMonth.toString().padLeft(2, '0')}-${endMonth.toString().padLeft(2, '0')}月';
}

List<String> invoicePeriodOptionsForGregorianYear(int year) {
  return List<String>.unmodifiable(
    List<String>.generate(
      6,
      (index) => formatInvoicePeriodForDate(DateTime(year, index * 2 + 1, 1)),
    ),
  );
}

DateTime? parseInvoiceReviewDate(String raw) {
  final normalized = raw
      .trim()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('/', '-')
      .replaceAll('.', '-');
  final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(normalized);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final value = DateTime(year, month, day);
  if (value.year != year || value.month != month || value.day != day) return null;
  return value;
}

String deriveInvoicePeriodFromDateText(String rawDate) {
  final date = parseInvoiceReviewDate(rawDate);
  return date == null ? '' : formatInvoicePeriodForDate(date);
}
