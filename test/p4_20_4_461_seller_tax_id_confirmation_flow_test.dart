import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_identity_review_service.dart';
import 'package:my_finance_app/features/invoice/invoice_seller_tax_id_confirmation.dart';
import 'package:my_finance_app/features/invoice/invoice_seller_tax_id_confirmation_flow.dart';
import 'package:my_finance_app/features/merchant/business_registry_repository.dart';
import 'package:my_finance_app/features/merchant/merchant_identity_resolution_policy.dart';
import 'package:my_finance_app/features/merchant/merchant_record.dart';

void main() {
  const flow = InvoiceSellerTaxIdConfirmationFlow();

  test('31655572 explicit user confirmation happens before local lookup', () async {
    final port = _RecordingReviewPort();
    const initial = InvoiceSellerTaxIdConfirmationState(
      currentSellerTaxId: '31655572',
      currentSourceToken: 'ocr',
    );

    final before = flow.synchronize(
      confirmationState: initial,
      sellerIdentifier: '31655572',
      sourceToken: 'ocr',
      localQrAuthority: false,
      explicitlyCorrected: false,
      explicitlyAiSelected: false,
      aiComparisonAcknowledged: false,
      initialLocalSellerIdentifierSource: 'ocr',
    );
    expect(before.authoritative, isFalse);
    expect(before.lookupPerformed, isFalse);
    expect(port.resolveCalls, 0);

    final after = await flow.confirmAndResolve(
      confirmationState: before.confirmationState,
      sellerIdentifier: '31655572',
      sourceToken: 'ocr',
      localQrAuthority: false,
      explicitlyCorrected: false,
      explicitlyAiSelected: false,
      aiComparisonAcknowledged: false,
      initialLocalSellerIdentifierSource: 'ocr',
      literalMerchantText: '辨識商家',
      reviewPort: port,
    );

    expect(after.confirmationState.explicitlyConfirmedForCurrentValue, isTrue);
    expect(after.authoritative, isTrue);
    expect(after.lookupPerformed, isTrue);
    expect(port.resolveCalls, 1);
    expect(port.lastSellerIdentifier, '31655572');
    expect(port.lastSellerIdentifierAuthoritative, isTrue);
  });

  test('stale 31655572 authority cannot leak to 60282181', () async {
    final port = _RecordingReviewPort();
    final confirmed316 = (await flow.confirmAndResolve(
      confirmationState: const InvoiceSellerTaxIdConfirmationState(
        currentSellerTaxId: '31655572',
        currentSourceToken: 'ocr',
      ),
      sellerIdentifier: '31655572',
      sourceToken: 'ocr',
      localQrAuthority: false,
      explicitlyCorrected: false,
      explicitlyAiSelected: false,
      aiComparisonAcknowledged: false,
      initialLocalSellerIdentifierSource: 'ocr',
      literalMerchantText: '第一商家',
      reviewPort: port,
    )).confirmationState;
    expect(port.resolveCalls, 1);

    final stale = flow.synchronize(
      confirmationState: confirmed316,
      sellerIdentifier: '60282181',
      sourceToken: 'ocr',
      localQrAuthority: false,
      explicitlyCorrected: false,
      explicitlyAiSelected: false,
      aiComparisonAcknowledged: false,
      initialLocalSellerIdentifierSource: 'ocr',
    );

    expect(stale.confirmationState.explicitlyConfirmedForCurrentValue, isFalse);
    expect(stale.authoritative, isFalse);
    expect(stale.lookupPerformed, isFalse);
    expect(port.resolveCalls, 1);

    final reconfirmed = await flow.confirmAndResolve(
      confirmationState: stale.confirmationState,
      sellerIdentifier: '60282181',
      sourceToken: 'ocr',
      localQrAuthority: false,
      explicitlyCorrected: false,
      explicitlyAiSelected: false,
      aiComparisonAcknowledged: false,
      initialLocalSellerIdentifierSource: 'ocr',
      literalMerchantText: '第二商家',
      reviewPort: port,
    );
    expect(reconfirmed.authoritative, isTrue);
    expect(reconfirmed.lookupPerformed, isTrue);
    expect(port.resolveCalls, 2);
    expect(port.lastSellerIdentifier, '60282181');
  });
}

class _RecordingReviewPort implements InvoiceMerchantIdentityReviewPort {
  int resolveCalls = 0;
  String lastSellerIdentifier = '';
  bool lastSellerIdentifierAuthoritative = false;

  @override
  Future<InvoiceMerchantIdentityReviewContext> resolve({
    required String sellerIdentifier,
    required bool sellerIdentifierAuthoritative,
    required String literalMerchantText,
  }) async {
    resolveCalls += 1;
    lastSellerIdentifier = sellerIdentifier;
    lastSellerIdentifierAuthoritative = sellerIdentifierAuthoritative;
    return InvoiceMerchantIdentityReviewContext(
      decision: MerchantIdentityResolutionDecision(
        literalMerchantText: literalMerchantText,
        sellerIdentifier: sellerIdentifier,
        registryLookupAllowed: sellerIdentifierAuthoritative,
        officialLegalNameSuggestion: '官方登記名稱',
        formalMerchantName: '',
        requiresBrandConfirmation: true,
        reason: MerchantIdentityResolutionReason.registryLegalNameNeedsBrandConfirmation,
      ),
      registryStatus: BusinessRegistryLookupStatus.hit,
      registryVersion: 'fixture-v1',
      registryCoverage: 'full',
      registrySourceDataDate: '2026-09-11',
      registryRefreshAttempted: false,
      registryRefreshError: '',
    );
  }

  @override
  Future<InvoiceMerchantIdentityReviewContext> confirmBinding({
    required MerchantRecord merchant,
    required String sellerIdentifier,
    required String literalMerchantText,
    required String evidenceSource,
    required String sourceReference,
  }) {
    throw UnimplementedError('not used by sellerTaxId confirmation flow');
  }
}
