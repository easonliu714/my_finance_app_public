import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/google_mlkit_traditional_invoice_recognizer.dart';
import 'package:my_finance_app/features/invoice/invoice_live_capture_adaptive_page.dart';

void main() {
  const expected = '12345675'; // Synthetic checksum-valid fixture only.

  test('Frozen seller-tax evidence accepts only the exact stable value', () {
    const evidence = TraditionalSellerTaxIdEvidence(
      value: expected,
      source: 'synthetic_exact',
      checksumValid: true,
      strongContext: true,
    );

    expect(
      isExactFrozenSellerTaxEvidence(
        expectedSellerTaxId: expected,
        evidence: evidence,
      ),
      isTrue,
    );
  });

  test('checksum-invalid evidence cannot satisfy Frozen exact match', () {
    const evidence = TraditionalSellerTaxIdEvidence(
      value: expected,
      source: 'synthetic_invalid_checksum',
      checksumValid: false,
      strongContext: true,
    );

    expect(
      isExactFrozenSellerTaxEvidence(
        expectedSellerTaxId: expected,
        evidence: evidence,
      ),
      isFalse,
    );
  });

  test('different accepted seller-tax value cannot replace Live identity', () {
    const evidence = TraditionalSellerTaxIdEvidence(
      value: '99000002',
      source: 'synthetic_other',
      checksumValid: true,
      strongContext: true,
    );

    expect(
      isExactFrozenSellerTaxEvidence(
        expectedSellerTaxId: expected,
        evidence: evidence,
      ),
      isFalse,
    );
  });

  test('empty expected Live identity never passes Frozen fallback', () {
    const evidence = TraditionalSellerTaxIdEvidence(
      value: expected,
      source: 'synthetic_exact',
      checksumValid: true,
      strongContext: true,
    );

    expect(
      isExactFrozenSellerTaxEvidence(
        expectedSellerTaxId: '',
        evidence: evidence,
      ),
      isFalse,
    );
  });
}
