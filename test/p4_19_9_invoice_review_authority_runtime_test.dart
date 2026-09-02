import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_review_authority_contract.dart';
import 'package:my_finance_app/features/invoice/invoice_review_authority_runtime_adapter.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_view_model.dart';

void main() {
  const adapter = InvoiceReviewAuthorityRuntimeAdapter();

  test('Local OCR core fields stay supplemental before explicit confirmation', () {
    final decision = adapter.evaluateTransactionDraft(review: _review());

    expect(decision.isReady, isFalse);
    expect(
      decision.reasonCode,
      InvoiceReviewAuthorityReasonCode.fieldNotAuthoritative,
    );
    expect(decision.blockingField, InvoiceReviewAuthorityFieldKind.invoiceId);
  });

  test('explicit review confirmation promotes non-QR core fields for handoff', () {
    final decision = adapter.evaluateTransactionDraft(
      review: _review(),
      explicitCoreConfirmation: true,
    );

    expect(decision.isReady, isTrue);
    expect(decision.reasonCode, InvoiceReviewAuthorityReasonCode.ready);
  });

  test('QR evidence is formal authority without silently promoting OCR', () {
    final review = _review(
      invoiceConfidence: 'QR 解析',
      dateConfidence: 'QR 解析',
      timeConfidence: 'OCR 高',
      amountConfidence: 'QR 解析',
    );

    final invoiceAuthority = adapter.authorityForField(
      review.fieldFor(InvoiceReviewFieldKey.invoiceNumber)!,
    );
    final timeAuthority = adapter.authorityForField(
      review.fieldFor(InvoiceReviewFieldKey.invoiceTime)!,
    );

    expect(invoiceAuthority!.isFormalHandoffAuthority, isTrue);
    expect(invoiceAuthority.source, InvoiceReviewAuthoritySource.qrPayload);
    expect(timeAuthority!.isFormalHandoffAuthority, isFalse);
    expect(timeAuthority.source, InvoiceReviewAuthoritySource.localOcr);
  });

  test('explicit user correction becomes field authority', () {
    final review = _review();
    final authority = adapter.authorityForField(
      review.fieldFor(InvoiceReviewFieldKey.invoiceTime)!,
      explicitlyCorrected: true,
    );

    expect(authority!.isFormalHandoffAuthority, isTrue);
    expect(
      authority.source,
      InvoiceReviewAuthoritySource.explicitUserCorrection,
    );
  });

  test('recognized merchant remains outside transaction core authority gate', () {
    final review = _review(merchant: 'OCR 候選商家');
    final decision = adapter.evaluateTransactionDraft(
      review: review,
      explicitCoreConfirmation: true,
    );
    final merchantAuthority = adapter.authorityForField(
      review.fieldFor(InvoiceReviewFieldKey.sellerName)!,
      explicitlyConfirmed: true,
    );

    expect(decision.isReady, isTrue);
    expect(merchantAuthority!.isFormalHandoffAuthority, isFalse);
    expect(merchantAuthority.source, InvoiceReviewAuthoritySource.localOcr);
  });

  test('missing core field still fails closed even with explicit confirmation', () {
    final decision = adapter.evaluateTransactionDraft(
      review: _review(time: ''),
      explicitCoreConfirmation: true,
    );

    expect(decision.isReady, isFalse);
    expect(decision.reasonCode, InvoiceReviewAuthorityReasonCode.fieldMissing);
    expect(decision.blockingField, InvoiceReviewAuthorityFieldKind.issueTime);
  });
}

InvoiceReviewFormViewModel _review({
  String invoiceNumber = 'AB12345678',
  String date = '2026-08-24',
  String time = '20:18',
  String amount = '72',
  String merchant = 'OK便利商店',
  String invoiceConfidence = 'OCR 高',
  String dateConfidence = 'OCR 高',
  String timeConfidence = 'OCR 高',
  String amountConfidence = 'OCR 高',
}) {
  return InvoiceReviewFormViewModel(
    title: '發票人工覆核',
    routeReason: 'runtime authority test',
    disclaimer: 'test',
    fields: <InvoiceReviewFieldViewModel>[
      _field(
        InvoiceReviewFieldKey.invoiceNumber,
        '發票號碼',
        invoiceNumber,
        invoiceConfidence,
      ),
      _field(
        InvoiceReviewFieldKey.invoiceDate,
        '發票日期',
        date,
        dateConfidence,
      ),
      _field(
        InvoiceReviewFieldKey.invoiceTime,
        '交易時間',
        time,
        timeConfidence,
      ),
      _field(
        InvoiceReviewFieldKey.totalAmount,
        '總金額',
        amount,
        amountConfidence,
      ),
      _field(
        InvoiceReviewFieldKey.sellerName,
        '商家名稱',
        merchant,
        'OCR 中',
      ),
    ],
    lineItems: const <InvoiceReviewLineItemViewModel>[],
    warnings: const <String>[],
    availableOverrides: const [],
    canOpenReview: true,
    requiresAcknowledgement: false,
    disclaimerAcknowledged: true,
  );
}

InvoiceReviewFieldViewModel _field(
  InvoiceReviewFieldKey key,
  String label,
  String value,
  String confidence,
) {
  return InvoiceReviewFieldViewModel(
    key: key,
    label: label,
    value: value,
    editable: true,
    requiredForReview: false,
    confidenceLabel: confidence,
  );
}
