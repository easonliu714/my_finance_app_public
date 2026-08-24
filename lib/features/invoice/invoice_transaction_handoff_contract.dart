import 'invoice_review_form_view_model.dart';

class InvoiceTransactionHandoffDraft {
  const InvoiceTransactionHandoffDraft({
    required this.reviewConfirmed,
    required this.amount,
    required this.occurredAt,
    required this.recognizedMerchantCandidate,
    required this.formalMerchantName,
    required this.formalAccountName,
    required this.formalCategory,
    required this.invoiceNumber,
    required this.sellerTaxId,
    required this.invoicePeriod,
    required this.randomCode,
    required this.note,
    required this.warnings,
  });

  final bool reviewConfirmed;
  final double? amount;
  final DateTime? occurredAt;

  /// Recognition evidence only. This value never authorizes a formal merchant
  /// mapping by itself.
  final String recognizedMerchantCandidate;

  /// Formal accounting selections. Empty means the user still has to choose
  /// an existing master row (or explicitly create one through the governed UI).
  final String formalMerchantName;
  final String formalAccountName;
  final String formalCategory;

  final String invoiceNumber;
  final String sellerTaxId;
  final String invoicePeriod;
  final String randomCode;
  final String note;
  final List<String> warnings;

  bool get requiresExplicitMerchantSelection => formalMerchantName.isEmpty;
  bool get requiresExplicitAccountSelection => formalAccountName.isEmpty;
  bool get requiresExplicitCategorySelection => formalCategory.isEmpty;

  bool get coreInvoiceFieldsReady =>
      reviewConfirmed && amount != null && amount! > 0 && occurredAt != null;

  /// Opening an editable transaction draft is allowed once the invoice review
  /// itself is confirmed and the amount/date-time are usable. Missing formal
  /// master selections remain explicit blockers for the final Save boundary.
  bool get canOpenTransactionDraft => coreInvoiceFieldsReady;

  bool get canSaveFormalTransaction =>
      coreInvoiceFieldsReady &&
      !requiresExplicitMerchantSelection &&
      !requiresExplicitAccountSelection &&
      !requiresExplicitCategorySelection;
}

class InvoiceTransactionHandoffContract {
  const InvoiceTransactionHandoffContract();

  InvoiceTransactionHandoffDraft build({
    required InvoiceReviewFormViewModel review,
    required bool reviewConfirmed,
    String formalMerchantName = '',
    String formalAccountName = '',
    String formalCategory = '',
  }) {
    final amountText = _field(review, InvoiceReviewFieldKey.totalAmount);
    final amount = _parsePositiveAmount(amountText);
    final occurredAt = _parseOccurredAt(
      _field(review, InvoiceReviewFieldKey.invoiceDate),
      _field(review, InvoiceReviewFieldKey.invoiceTime),
    );
    final recognizedMerchantCandidate =
        _field(review, InvoiceReviewFieldKey.sellerName);
    final invoiceNumber = _field(review, InvoiceReviewFieldKey.invoiceNumber);
    final sellerTaxId = _field(review, InvoiceReviewFieldKey.sellerTaxId);
    final invoicePeriod = _field(review, InvoiceReviewFieldKey.invoicePeriod);
    final randomCode = _field(review, InvoiceReviewFieldKey.randomCode);

    final normalizedMerchant = formalMerchantName.trim();
    final normalizedAccount = formalAccountName.trim();
    final normalizedCategory = formalCategory.trim();
    final warnings = <String>[
      if (!reviewConfirmed) 'REVIEW_CONFIRMATION_REQUIRED',
      if (amount == null) 'TOTAL_AMOUNT_REQUIRED_OR_INVALID',
      if (occurredAt == null) 'INVOICE_DATE_TIME_REQUIRED_OR_INVALID',
      if (normalizedMerchant.isEmpty) 'FORMAL_MERCHANT_SELECTION_REQUIRED',
      if (normalizedAccount.isEmpty) 'FORMAL_ACCOUNT_SELECTION_REQUIRED',
      if (normalizedCategory.isEmpty) 'FORMAL_CATEGORY_SELECTION_REQUIRED',
    ];

    return InvoiceTransactionHandoffDraft(
      reviewConfirmed: reviewConfirmed,
      amount: amount,
      occurredAt: occurredAt,
      recognizedMerchantCandidate: recognizedMerchantCandidate,
      formalMerchantName: normalizedMerchant,
      formalAccountName: normalizedAccount,
      formalCategory: normalizedCategory,
      invoiceNumber: invoiceNumber,
      sellerTaxId: sellerTaxId,
      invoicePeriod: invoicePeriod,
      randomCode: randomCode,
      note: _buildGovernedNote(
        invoiceNumber: invoiceNumber,
        sellerTaxId: sellerTaxId,
        invoicePeriod: invoicePeriod,
        randomCode: randomCode,
      ),
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  static String _field(
    InvoiceReviewFormViewModel review,
    InvoiceReviewFieldKey key,
  ) => review.fieldFor(key)?.value.trim() ?? '';

  static double? _parsePositiveAmount(String raw) {
    final normalized = raw.replaceAll(',', '').trim();
    final value = double.tryParse(normalized);
    if (value == null || !value.isFinite || value <= 0) return null;
    return value;
  }

  static DateTime? _parseOccurredAt(String rawDate, String rawTime) {
    final date = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(rawDate.trim());
    final time = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?$')
        .firstMatch(rawTime.trim());
    if (date == null || time == null) return null;

    final year = int.parse(date.group(1)!);
    final month = int.parse(date.group(2)!);
    final day = int.parse(date.group(3)!);
    final hour = int.parse(time.group(1)!);
    final minute = int.parse(time.group(2)!);
    final second = int.tryParse(time.group(3) ?? '') ?? 0;
    final value = DateTime(year, month, day, hour, minute, second);
    if (value.year != year ||
        value.month != month ||
        value.day != day ||
        value.hour != hour ||
        value.minute != minute ||
        value.second != second) {
      return null;
    }
    return value;
  }

  static String _buildGovernedNote({
    required String invoiceNumber,
    required String sellerTaxId,
    required String invoicePeriod,
    required String randomCode,
  }) {
    final lines = <String>['來源：發票辨識人工覆核'];
    if (invoiceNumber.isNotEmpty) lines.add('發票號碼：$invoiceNumber');
    if (sellerTaxId.isNotEmpty) lines.add('賣方統編：$sellerTaxId');
    if (invoicePeriod.isNotEmpty) lines.add('發票期別：$invoicePeriod');
    if (randomCode.isNotEmpty) lines.add('隨機碼：$randomCode');
    return lines.join('\n');
  }
}
