import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_settings.dart';

void main() {
  test('fresh and blank-model settings default to Gemini 3.1 Flash-Lite', () {
    expect(
      const GeminiInvoiceSettings().model,
      'gemini-3.1-flash-lite',
    );
    expect(
      GeminiInvoiceSettings.decode(null).model,
      'gemini-3.1-flash-lite',
    );
    expect(
      GeminiInvoiceSettings.decode(
        '{"schemaVersion":4,"apiKeys":[],"model":"   "}',
      ).model,
      'gemini-3.1-flash-lite',
    );
  });

  test('legacy explicit model remains authoritative after default change', () {
    final settings = GeminiInvoiceSettings.decode(
      '{"schemaVersion":4,"apiKeys":[],"model":"gemini-3.6-flash"}',
    );

    expect(settings.model, 'gemini-3.6-flash');
  });

  test('legacy v3 grouped settings migrate into one flat key pool', () {
    final settings = GeminiInvoiceSettings.decode(
      '{"schemaVersion":3,"apiKeys":["KEY_A","KEY_B"],"keyGroups":[{"alias":"GROUP_A","apiKeys":["KEY_A","KEY_B"]}],"model":"gemini-3.6-flash","experimentalInvoiceVisionEnabled":true,"autoReviewLowConfidenceEnabled":false}',
    );

    expect(settings.apiKeys, <String>['KEY_A', 'KEY_B']);
    expect(settings.keyGroups, isEmpty);
    expect(settings.effectiveApiKeys, <String>['KEY_A', 'KEY_B']);
    expect(settings.model, 'gemini-3.6-flash');
    // Repairs the P4.19.1 real-device state where the switch looked enabled
    // but schema <=3 persisted autoReview=false until an explicit Save.
    expect(settings.autoReviewLowConfidenceEnabled, isTrue);
  });

  test('one input accepts multiple separators and deduplicates keys', () {
    final keys = GeminiInvoiceSettings.parseApiKeys(
      'KEY_A，KEY_B KEY_C\nKEY_B；KEY_D、KEY_E',
    );

    expect(keys, <String>['KEY_A', 'KEY_B', 'KEY_C', 'KEY_D', 'KEY_E']);
  });

  test('schema v4 round trip preserves flat key order without groups', () {
    const settings = GeminiInvoiceSettings(
      apiKeys: <String>['KEY_A', 'KEY_B', 'KEY_C'],
      experimentalInvoiceVisionEnabled: true,
      autoReviewLowConfidenceEnabled: true,
    );

    final encoded = settings.encode();
    final decoded = GeminiInvoiceSettings.decode(encoded);

    expect(decoded.effectiveApiKeys, <String>['KEY_A', 'KEY_B', 'KEY_C']);
    expect(decoded.keyGroups, isEmpty);
    expect(decoded.model, 'gemini-3.1-flash-lite');
    expect(decoded.experimentalInvoiceVisionEnabled, isTrue);
    expect(decoded.autoReviewLowConfidenceEnabled, isTrue);
  });

  test('legacy compatibility projection exposes anonymous key slots only', () {
    const settings = GeminiInvoiceSettings(
      apiKeys: <String>['KEY_A', 'KEY_B'],
    );

    expect(settings.effectiveKeyGroups, hasLength(2));
    expect(settings.effectiveKeyGroups[0].alias, 'KEY_1');
    expect(settings.effectiveKeyGroups[0].apiKeys, <String>['KEY_A']);
    expect(settings.effectiveKeyGroups[1].alias, 'KEY_2');
    expect(settings.effectiveKeyGroups[1].apiKeys, <String>['KEY_B']);
  });
}
