import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/google_mlkit_traditional_invoice_recognizer.dart';
import 'package:my_finance_app/features/invoice/invoice_live_capture_page.dart';
import 'package:my_finance_app/features/invoice/invoice_live_field_readiness.dart';

void main() {
  const merchantHeader = <String>[
    'ZZ00000001',
    '測試商店',
  ];

  test('bounded weak-label OCR variants admit checksum-valid seller tax ID', () {
    for (final label in <String>['NO', 'N0', 'HO', 'H0']) {
      final evidence = extractTraditionalSellerTaxIdEvidence(<String>[
        ...merchantHeader,
        '$label.00000058',
      ]);
      expect(evidence?.value, '00000058', reason: label);
      expect(evidence?.source, 'contextual_no_header', reason: label);
      expect(evidence?.checksumValid, isTrue, reason: label);
      expect(evidence?.acceptedForLive, isTrue, reason: label);
    }
  });

  test('S-to-5 repair is allowed only behind a seller-tax label', () {
    final labeled = extractTraditionalSellerTaxIdEvidence(const <String>[
      'ZZ00000001',
      '測試商店',
      'NO.000000S8',
    ]);
    final unlabeled = extractTraditionalSellerTaxIdEvidence(const <String>[
      'ZZ00000001',
      '測試商店',
      '000000S8',
    ]);

    expect(labeled?.value, '00000058');
    expect(labeled?.checksumValid, isTrue);
    expect(labeled?.acceptedForLive, isTrue);
    expect(unlabeled, isNull);
  });

  test('weak-label path still rejects phone-like and checksum-invalid evidence', () {
    final phoneLike = extractTraditionalSellerTaxIdEvidence(const <String>[
      'ZZ00000001',
      '測試商店',
      'TEL.00000058',
    ]);
    final checksumInvalid = extractTraditionalSellerTaxIdEvidence(const <String>[
      'ZZ00000001',
      '測試商店',
      'N0.00000059',
    ]);

    expect(phoneLike, isNull);
    expect(checksumInvalid, isNull);
  });

  test('traditional freeze still needs two identical accepted observations', () {
    const consensus = TraditionalLiveIdentityConsensus(
      invoiceNumber: 'ZZ00000001',
      invoiceObservations: 2,
      identityContextObservations: 2,
      currentFrameRelevant: true,
    );

    final first = resolveInvoiceLiveFieldReadiness(
      consensus: consensus,
      invoiceNumber: 'ZZ00000001',
      sellerTaxId: '00000064',
      hasSellerIdentityContext: true,
      previousSignature: '',
      previousConsecutiveObservations: 0,
      profile: InvoiceLiveReadinessProfile.traditionalExplicitSellerTax,
    );
    final changed = resolveInvoiceLiveFieldReadiness(
      consensus: consensus,
      invoiceNumber: 'ZZ00000001',
      sellerTaxId: '00000058',
      hasSellerIdentityContext: true,
      previousSignature: first.signature,
      previousConsecutiveObservations: first.consecutiveObservations,
      profile: InvoiceLiveReadinessProfile.traditionalExplicitSellerTax,
    );
    final repeated = resolveInvoiceLiveFieldReadiness(
      consensus: consensus,
      invoiceNumber: 'ZZ00000001',
      sellerTaxId: '00000058',
      hasSellerIdentityContext: true,
      previousSignature: changed.signature,
      previousConsecutiveObservations: changed.consecutiveObservations,
      profile: InvoiceLiveReadinessProfile.traditionalExplicitSellerTax,
    );

    expect(first.stableObservations, 1);
    expect(first.canFreeze, isFalse);
    expect(changed.stableObservations, 1);
    expect(changed.canFreeze, isFalse);
    expect(repeated.stableObservations, 2);
    expect(repeated.canFreeze, isTrue);
  });
}
