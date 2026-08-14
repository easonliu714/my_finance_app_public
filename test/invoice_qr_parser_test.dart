import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_import_staging.dart';
import 'package:my_finance_app/features/invoice/invoice_qr_parser.dart';
import 'package:my_finance_app/features/invoice/manual_invoice_draft.dart';

void main() {
  const parser = InvoiceQrParser();

  test('parse returns basic fields from left QR payload', () {
    const payload = 'AB123456781150609123400000064000000780000000024531234abcdefghijklmnopqrstuvwx:extra';

    final result = parser.parse(payload);

    expect(result.errors, isEmpty);
    expect(result.invoiceNumber, 'AB12345678');
    expect(result.invoiceDate, DateTime(2026, 6, 9));
    expect(result.randomCode, '1234');
    expect(result.salesAmount, 100);
    expect(result.totalAmount, 120);
    expect(result.buyerIdentifier, '00000000');
    expect(result.sellerIdentifier, '24531234');
    expect(result.warnings, contains('QR payload 含延伸明細，本階段僅解析前段基本資料'));
  });

  test('parse exposes review status and public-safe source label', () {
    const payload = 'AB123456781150609123400000064000000780000000024531234abcdefghijklmnopqrstuvwx';

    final result = parser.parse(payload);

    expect(result.reviewStatus, InvoiceQrParseReviewStatus.ready);
    expect(result.reviewStatusLabel, '可匯入');
    expect(result.sourceLabel, 'QR Code 離線解析');
    expect(result.canStageCandidate, isTrue);
    expect(result.requiresManualReview, isFalse);
    expect(result.hasWarnings, isFalse);
    expect(result.hasErrors, isFalse);
  });

  test('parse with extension remains stageable but requires review', () {
    const payload = 'AB123456781150609123400000064000000780000000024531234abcdefghijklmnopqrstuvwx:extra';

    final result = parser.parse(payload);

    expect(result.reviewStatus, InvoiceQrParseReviewStatus.needsReview);
    expect(result.reviewStatusLabel, '可匯入，需確認');
    expect(result.canStageCandidate, isTrue);
    expect(result.requiresManualReview, isTrue);
    expect(result.warningSummary, contains('QR payload 含延伸明細'));
  });

  test('parse malformed payload returns errors without throwing', () {
    final result = parser.parse('AB123');

    expect(result.isValid, isFalse);
    expect(result.reviewStatus, InvoiceQrParseReviewStatus.blocked);
    expect(result.reviewStatusLabel, '不可匯入');
    expect(result.canStageCandidate, isFalse);
    expect(result.errorSummary, contains('QR payload 長度不足'));
    expect(result.errors, contains('QR payload 長度不足，無法解析電子發票左方 QR 基本資料'));
  });

  test('parse right side detail QR is unsupported in POC', () {
    final result = parser.parse('**商品明細');

    expect(result.isValid, isFalse);
    expect(result.errors, contains('目前 POC 僅支援電子發票左方 QR 基本資料，不支援右方明細 QR'));
  });

  test('toManualInvoiceDraftCandidate requires explicit caller action', () {
    const payload = 'AB123456781150609123400000064000000780000000024531234abcdefghijklmnopqrstuvwx';

    final result = parser.parse(payload);
    final draft = result.toManualInvoiceDraftCandidate(
      id: 'draft-qr-1',
      sellerName: '測試便利商店',
      note: 'QR 匯入候選',
      now: DateTime.utc(2026, 6, 10),
    );

    expect(draft.id, 'draft-qr-1');
    expect(draft.invoiceNumber, 'AB12345678');
    expect(draft.invoiceDate, DateTime(2026, 6, 9));
    expect(draft.sellerName, '測試便利商店');
    expect(draft.totalAmount, 120);
    expect(draft.note, 'QR 匯入候選');
    expect(draft.status, ManualInvoiceDraftStatus.readyToReview);
  });

  test('toStagingItemCandidate keeps QR output review-first', () {
    const payload = 'AB123456781150609123400000064000000780000000024531234abcdefghijklmnopqrstuvwx';

    final result = parser.parse(payload);
    final item = result.toStagingItemCandidate(
      id: 'stage-qr-1',
      sellerName: '',
      note: 'QR parser POC',
      now: DateTime.utc(2026, 6, 10),
    );

    expect(item.id, 'stage-qr-1');
    expect(item.source, InvoiceImportStagingSource.qrParser);
    expect(item.status, InvoiceImportStagingStatus.pending);
    expect(item.invoiceNumber, 'AB12345678');
    expect(item.invoiceDate, DateTime(2026, 6, 9));
    expect(item.sellerName, '賣方統編 24531234');
    expect(item.totalAmount, 120);
    expect(item.rawPayload, payload);
    expect(item.isConvertible, isFalse);
  });

  test('toStagingItemCandidate carries review warning in note', () {
    const payload = 'AB123456781150609123400000064000000780000000024531234abcdefghijklmnopqrstuvwx:extra';

    final result = parser.parse(payload);
    final item = result.toStagingItemCandidate(
      id: 'stage-qr-1',
      sellerName: '',
      note: 'QR parser POC',
      now: DateTime.utc(2026, 6, 10),
    );

    expect(item.status, InvoiceImportStagingStatus.pending);
    expect(item.note, contains('QR parser POC'));
    expect(item.note, contains('QR 警示：QR payload 含延伸明細，本階段僅解析前段基本資料'));
  });

  test('invalid parse result cannot be converted to draft candidate or staging item', () {
    final result = parser.parse('bad');

    expect(
      () => result.toManualInvoiceDraftCandidate(id: 'draft', sellerName: '店家'),
      throwsA(isA<StateError>()),
    );
    expect(
      () => result.toStagingItemCandidate(id: 'stage'),
      throwsA(isA<StateError>()),
    );
  });
}
