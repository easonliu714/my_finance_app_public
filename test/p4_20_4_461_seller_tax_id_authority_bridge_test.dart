import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_registry_corroboration_policy.dart';
import 'package:my_finance_app/features/invoice/invoice_seller_tax_id_authority_bridge.dart';
import 'package:my_finance_app/features/invoice/invoice_seller_tax_id_confirmation.dart';

void main() {
  const bridge = InvoiceSellerTaxIdAuthorityBridge();

  test('exact confirmed weak OCR value may authorize local Registry lookup', () {
    final confirmed = const InvoiceSellerTaxIdConfirmationState(
      currentSellerTaxId: '31655572',
      currentSourceToken: 'ocr',
    ).confirmCurrent();

    final result = bridge.evaluate(
      confirmationState: confirmed,
      sellerIdentifier: '31655572',
      sourceToken: 'ocr',
      localQrAuthority: false,
      explicitlyCorrected: false,
      explicitlyAiSelected: false,
      aiComparisonAcknowledged: false,
      initialLocalSellerIdentifierSource: 'ocr',
    );

    expect(result.confirmationState.explicitlyConfirmedForCurrentValue, isTrue);
    expect(result.authoritative, isTrue);
    expect(
      result.decision.source,
      InvoiceRegistryCorroborationAuthoritySource.explicitUserCorrection,
    );
  });

  test('sellerTaxId value change invalidates old authority before evaluation', () {
    final confirmed = const InvoiceSellerTaxIdConfirmationState(
      currentSellerTaxId: '31655572',
      currentSourceToken: 'ocr',
    ).confirmCurrent();

    final result = bridge.evaluate(
      confirmationState: confirmed,
      sellerIdentifier: '60282181',
      sourceToken: 'ocr',
      localQrAuthority: false,
      explicitlyCorrected: false,
      explicitlyAiSelected: false,
      aiComparisonAcknowledged: false,
      initialLocalSellerIdentifierSource: 'ocr',
    );

    expect(result.confirmationState.explicitlyConfirmedForCurrentValue, isFalse);
    expect(result.confirmationState.confirmedSellerTaxId, isEmpty);
    expect(result.authoritative, isFalse);
  });

  test('sellerTaxId source change invalidates old authority before evaluation', () {
    final confirmed = const InvoiceSellerTaxIdConfirmationState(
      currentSellerTaxId: '31655572',
      currentSourceToken: 'ocr',
    ).confirmCurrent();

    final result = bridge.evaluate(
      confirmationState: confirmed,
      sellerIdentifier: '31655572',
      sourceToken: 'ai',
      localQrAuthority: false,
      explicitlyCorrected: false,
      explicitlyAiSelected: true,
      aiComparisonAcknowledged: true,
      initialLocalSellerIdentifierSource: 'ocr',
    );

    expect(result.confirmationState.explicitlyConfirmedForCurrentValue, isFalse);
    expect(result.confirmationState.confirmedSourceToken, isEmpty);
    expect(result.authoritative, isFalse);
    expect(
      result.decision.reason,
      'ai_selection_requires_explicit_user_confirmation',
    );
  });

  test('reconfirming changed sellerTaxId restores only the new exact authority', () {
    final changed = const InvoiceSellerTaxIdConfirmationState(
      currentSellerTaxId: '60282181',
      currentSourceToken: 'ocr',
    ).confirmCurrent();

    final result = bridge.evaluate(
      confirmationState: changed,
      sellerIdentifier: '60282181',
      sourceToken: 'ocr',
      localQrAuthority: false,
      explicitlyCorrected: false,
      explicitlyAiSelected: false,
      aiComparisonAcknowledged: false,
      initialLocalSellerIdentifierSource: 'ocr',
    );

    expect(result.confirmationState.normalizedSellerTaxId, '60282181');
    expect(result.confirmationState.explicitlyConfirmedForCurrentValue, isTrue);
    expect(result.authoritative, isTrue);
  });
}
