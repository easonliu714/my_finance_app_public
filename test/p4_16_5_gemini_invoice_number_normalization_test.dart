import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_review.dart';

void main() {
  Map<String, Object?> payload(
    String invoiceNumber, {
    Object? sellerTaxId,
    String invoiceTime = '08:22:33',
    double? invoiceTimeConfidence,
  }) =>
      <String, Object?>{
        'invoiceNumber': invoiceNumber,
        'invoicePeriod': '113年07-08月',
        'sellerTaxId': sellerTaxId,
        'invoiceDate': '2024-08-13',
        'invoiceTime': invoiceTime,
        'merchantName': 'OK mart',
        'totalAmount': 9,
        'lineItems': <Object?>[],
        'confidence': <String, Object?>{
          if (invoiceTimeConfidence != null)
            'invoiceTime': invoiceTimeConfidence,
        },
        'warnings': <String>[],
      };

  test('normalizes a printed hyphen before invoice-number validation', () {
    final candidate = GeminiInvoiceReviewCandidate.fromJson(
      payload('CL-90000018'),
    );

    expect(candidate.invoiceNumber, 'CL90000018');
    expect(
      candidate.warnings,
      isNot(contains('AI 發票號碼格式不符，已保持空白。')),
    );
  });

  test('normalizes spaces but still rejects semantic garbage', () {
    final spaced = GeminiInvoiceReviewCandidate.fromJson(
      payload('CL 90000018'),
    );
    final invalid = GeminiInvoiceReviewCandidate.fromJson(
      payload('CL-9000001X'),
    );

    expect(spaced.invoiceNumber, 'CL90000018');
    expect(invalid.invoiceNumber, isEmpty);
    expect(invalid.warnings, contains('AI 發票號碼格式不符，已保持空白。'));
  });

  test('checksum-invalid AI seller tax ID is blanked instead of retained', () {
    final candidate = GeminiInvoiceReviewCandidate.fromJson(
      payload('AA90000002', sellerTaxId: '38340553'),
    );

    expect(candidate.sellerTaxId, isEmpty);
    expect(candidate.warnings, contains('AI 統一編號校驗未通過，已保持空白。'));
  });

  test('checksum-valid AI seller tax ID remains available for review', () {
    final candidate = GeminiInvoiceReviewCandidate.fromJson(
      payload('AA90000002', sellerTaxId: '30340553'),
    );

    expect(candidate.sellerTaxId, '30340553');
    expect(
      candidate.warnings,
      isNot(contains('AI 統一編號校驗未通過，已保持空白。')),
    );
  });

  test('low-confidence :00 seconds are blanked as unsafe completion', () {
    final candidate = GeminiInvoiceReviewCandidate.fromJson(
      payload(
        'AA90000002',
        invoiceTime: '11:35:00',
        invoiceTimeConfidence: 0.95,
      ),
    );

    expect(candidate.invoiceTime, isEmpty);
    expect(
      candidate.warnings,
      contains('AI 秒數為 00 且未達近乎確定可信度，為避免補零誤判已保持時間空白。'),
    );
  });

  test('near-certain exact :00 seconds remain available for review', () {
    final candidate = GeminiInvoiceReviewCandidate.fromJson(
      payload(
        'AA90000002',
        invoiceTime: '11:35:00',
        invoiceTimeConfidence: 0.99,
      ),
    );

    expect(candidate.invoiceTime, '11:35:00');
  });
}
