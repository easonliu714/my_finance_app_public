import 'invoice_award_official_dataset.dart';

/// Explicit, local-only invoice identity supplied by the user for award checks.
///
/// This contract intentionally has no transaction-write or network authority.
/// It prevents the live-draw MVP from inferring invoice identity from free-form
/// accounting notes.
class InvoiceAwardLocalMatchInput {
  const InvoiceAwardLocalMatchInput({
    required this.invoiceNumber,
    required this.invoiceDate,
  });

  final String invoiceNumber;
  final DateTime invoiceDate;

  String get normalizedInvoiceNumber =>
      invoiceNumber.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  bool get hasValidInvoiceNumber =>
      RegExp(r'^[A-Z]{2}\d{8}$').hasMatch(normalizedInvoiceNumber);

  OfficialInvoiceAwardPeriod get period {
    final rocYear = invoiceDate.year - 1911;
    final startMonth = invoiceDate.month.isOdd
        ? invoiceDate.month
        : invoiceDate.month - 1;
    return OfficialInvoiceAwardPeriod(
      rocYear: rocYear,
      startMonth: startMonth,
      endMonth: startMonth + 1,
    );
  }

  bool get isValid =>
      invoiceDate.year >= 1912 && hasValidInvoiceNumber && period.isCanonical;
}
