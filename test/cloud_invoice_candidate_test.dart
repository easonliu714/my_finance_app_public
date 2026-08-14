import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';

void main() {
  test('valid minimal candidate remains review-first and local-safe', () {
    final candidate = _candidate();

    expect(candidate.status, CloudInvoiceCandidateStatus.pending);
    expect(candidate.requiresUserReview, isTrue);
    expect(candidate.canCreateFormalTransactionAutomatically, isFalse);
    expect(candidate.canWriteMerchantAutomatically, isFalse);
    expect(candidate.canWriteAccountAutomatically, isFalse);
    expect(candidate.displaySellerName, '測試便利商店');
    expect(candidate.safeCarrierDisplay, '/AB***12');
  });

  test('source metadata separates public-safe and private research sources', () {
    expect(CloudInvoiceCandidateSource.manualEntry.metadata.label, '手動輸入');
    expect(CloudInvoiceCandidateSource.invoiceQrCode.metadata.label, 'QR Code 離線解析');
    expect(CloudInvoiceCandidateSource.mockCloudInvoice.metadata.label, '模擬雲端發票');
    expect(CloudInvoiceCandidateSource.receiptOcr.metadata.label, '拍照辨識候選');
    expect(CloudInvoiceCandidateSource.privateCloudResearch.metadata.label, '私有雲端實驗');

    expect(CloudInvoiceCandidateSource.manualEntry.metadata.isPublicReleaseSafe, isTrue);
    expect(CloudInvoiceCandidateSource.invoiceQrCode.metadata.isPublicReleaseSafe, isTrue);
    expect(CloudInvoiceCandidateSource.mockCloudInvoice.metadata.isPublicReleaseSafe, isTrue);
    expect(CloudInvoiceCandidateSource.receiptOcr.metadata.isPublicReleaseSafe, isFalse);
    expect(CloudInvoiceCandidateSource.privateCloudResearch.metadata.isPrivateResearchOnly, isTrue);

    for (final source in CloudInvoiceCandidateSource.values) {
      expect(source.metadata.supportsAutomaticBackgroundSync, isFalse);
    }
  });

  test('candidate exposes readable source labels and source boundaries', () {
    final candidate = _candidate(source: CloudInvoiceCandidateSource.invoiceQrCode);
    final privateCandidate = _candidate(source: CloudInvoiceCandidateSource.privateCloudResearch);

    expect(candidate.sourceLabel, 'QR Code 離線解析');
    expect(candidate.sourceShortLabel, 'QR');
    expect(candidate.isPublicReleaseSafeSource, isTrue);
    expect(candidate.isPrivateResearchSource, isFalse);
    expect(candidate.supportsAutomaticBackgroundSync, isFalse);

    expect(privateCandidate.sourceLabel, '私有雲端實驗');
    expect(privateCandidate.isPublicReleaseSafeSource, isFalse);
    expect(privateCandidate.isPrivateResearchSource, isTrue);
    expect(privateCandidate.supportsAutomaticBackgroundSync, isFalse);
  });

  test('valid candidate with items preserves line items as suggestions only', () {
    final candidate = _candidate(
      lineItems: const <CloudInvoiceLineItem>[
        CloudInvoiceLineItem(name: '鮮奶', quantity: 1, unitPrice: 95, amount: 95, categorySuggestion: '飲食'),
        CloudInvoiceLineItem(name: '麵包', quantity: 1, unitPrice: 35, amount: 35),
      ],
    );

    expect(candidate.hasLineItems, isTrue);
    expect(candidate.lineItems, hasLength(2));
    expect(candidate.lineItems.first.hasCategorySuggestion, isTrue);
    expect(candidate.lineItems.last.hasCategorySuggestion, isFalse);
    expect(candidate.canCreateFormalTransactionAutomatically, isFalse);
  });

  test('partial payload can stay pending with warnings and fallback seller label', () {
    final candidate = _candidate(
      sellerName: '',
      warnings: const <CloudInvoiceCandidateWarning>[
        CloudInvoiceCandidateWarning.missingSellerName,
        CloudInvoiceCandidateWarning.missingLineItems,
      ],
    );

    expect(candidate.status, CloudInvoiceCandidateStatus.pending);
    expect(candidate.hasWarnings, isTrue);
    expect(candidate.displaySellerName, '未命名雲端發票商家');
    expect(candidate.requiresUserReview, isTrue);
  });

  test('malformed payload can be represented as rejected without write capability', () {
    final candidate = _candidate(
      status: CloudInvoiceCandidateStatus.rejected,
      invoiceNumber: '',
      totalAmount: 0,
      errorCategory: CloudInvoiceCandidateErrorCategory.parseError,
      errorMessage: 'invalid amount',
    );

    expect(candidate.isRejected, isTrue);
    expect(candidate.hasError, isTrue);
    expect(candidate.requiresUserReview, isFalse);
    expect(candidate.canCreateFormalTransactionAutomatically, isFalse);
  });

  test('duplicate key is deterministic and normalized', () {
    final first = _candidate(invoiceNumber: 'ab12345678', sellerIdentifier: ' 12345678 ', totalAmount: 120.4);
    final second = _candidate(invoiceNumber: 'AB12345678', sellerIdentifier: '12345678', totalAmount: 120.4);

    expect(first.duplicateKey, second.duplicateKey);
    expect(first.duplicateKey, 'AB12345678|2026-06-09|120|12345678');
  });

  test('duplicate override is normalized and explicit', () {
    final candidate = _candidate(duplicateKeyOverride: ' custom-key ');

    expect(candidate.duplicateKey, 'CUSTOM-KEY');
  });

  test('authorization and unsupported carrier states remain rejected and safe', () {
    final authorization = _candidate(
      status: CloudInvoiceCandidateStatus.rejected,
      errorCategory: CloudInvoiceCandidateErrorCategory.authorization,
    );
    final unsupported = _candidate(
      status: CloudInvoiceCandidateStatus.rejected,
      errorCategory: CloudInvoiceCandidateErrorCategory.unsupportedCarrier,
    );

    expect(authorization.hasError, isTrue);
    expect(unsupported.hasError, isTrue);
    expect(authorization.canCreateFormalTransactionAutomatically, isFalse);
    expect(unsupported.canWriteMerchantAutomatically, isFalse);
  });

  test('retryable network state does not imply background retry or writes', () {
    final candidate = _candidate(
      status: CloudInvoiceCandidateStatus.retryableError,
      errorCategory: CloudInvoiceCandidateErrorCategory.network,
    );

    expect(candidate.isRetryable, isTrue);
    expect(candidate.requiresUserReview, isFalse);
    expect(candidate.canCreateFormalTransactionAutomatically, isFalse);
  });

  test('copyWith can update review state while preserving immutable source data', () {
    final candidate = _candidate();
    final duplicate = candidate.copyWith(status: CloudInvoiceCandidateStatus.duplicate);

    expect(duplicate.status, CloudInvoiceCandidateStatus.duplicate);
    expect(duplicate.invoiceNumber, candidate.invoiceNumber);
    expect(duplicate.requiresUserReview, isTrue);
  });
}

CloudInvoiceCandidate _candidate({
  CloudInvoiceCandidateSource source = CloudInvoiceCandidateSource.mockCloudInvoice,
  CloudInvoiceCandidateStatus status = CloudInvoiceCandidateStatus.pending,
  String invoiceNumber = 'AB12345678',
  DateTime? invoiceDate,
  String sellerIdentifier = '12345678',
  String sellerName = '測試便利商店',
  double totalAmount = 120,
  String carrierMaskedId = '/AB***12',
  List<CloudInvoiceLineItem> lineItems = const <CloudInvoiceLineItem>[],
  List<CloudInvoiceCandidateWarning> warnings = const <CloudInvoiceCandidateWarning>[],
  CloudInvoiceCandidateErrorCategory errorCategory = CloudInvoiceCandidateErrorCategory.none,
  String? errorMessage,
  String? duplicateKeyOverride,
}) {
  return CloudInvoiceCandidate(
    source: source,
    status: status,
    invoiceNumber: invoiceNumber,
    invoiceDate: invoiceDate ?? DateTime(2026, 6, 9),
    sellerIdentifier: sellerIdentifier,
    sellerName: sellerName,
    totalAmount: totalAmount,
    taxAmount: 6,
    carrierType: 'mobileBarcode',
    carrierMaskedId: carrierMaskedId,
    fetchedAt: DateTime.utc(2026, 6, 10, 8),
    lineItems: lineItems,
    rawPayload: 'mock-payload',
    warnings: warnings,
    errorCategory: errorCategory,
    errorMessage: errorMessage,
    duplicateKeyOverride: duplicateKeyOverride,
  );
}
