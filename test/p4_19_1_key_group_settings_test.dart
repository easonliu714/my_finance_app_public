import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_settings.dart';

void main() {
  test('legacy v2 flat keys migrate into one conservative quota group', () {
    final settings = GeminiInvoiceSettings.decode(
      '{"schemaVersion":2,"apiKeys":["KEY_A","KEY_B"],"model":"gemini-3.6-flash","experimentalInvoiceVisionEnabled":true}',
    );

    expect(settings.apiKeys, <String>['KEY_A', 'KEY_B']);
    expect(settings.effectiveKeyGroups, hasLength(1));
    expect(
      settings.effectiveKeyGroups.single.alias,
      GeminiInvoiceSettings.legacyGroupAlias,
    );
    expect(
      settings.effectiveKeyGroups.single.apiKeys,
      <String>['KEY_A', 'KEY_B'],
    );
  });

  test('each non-empty input line becomes one explicit independent group', () {
    final groups = GeminiInvoiceSettings.parseKeyGroups(
      'KEY_A1，KEY_A2\nKEY_B1\n\nKEY_C1；KEY_C2',
    );

    expect(groups.map((group) => group.alias), <String>[
      'GROUP_A',
      'GROUP_B',
      'GROUP_C',
    ]);
    expect(groups[0].apiKeys, <String>['KEY_A1', 'KEY_A2']);
    expect(groups[1].apiKeys, <String>['KEY_B1']);
    expect(groups[2].apiKeys, <String>['KEY_C1', 'KEY_C2']);
  });

  test('schema v3 round trip preserves explicit group boundaries', () {
    const settings = GeminiInvoiceSettings(
      apiKeys: <String>['KEY_A', 'KEY_B'],
      keyGroups: <GeminiInvoiceKeyGroup>[
        GeminiInvoiceKeyGroup(alias: 'GROUP_A', apiKeys: <String>['KEY_A']),
        GeminiInvoiceKeyGroup(alias: 'GROUP_B', apiKeys: <String>['KEY_B']),
      ],
      experimentalInvoiceVisionEnabled: true,
      autoReviewLowConfidenceEnabled: true,
    );

    final decoded = GeminiInvoiceSettings.decode(settings.encode());
    expect(decoded.effectiveKeyGroups, hasLength(2));
    expect(decoded.effectiveKeyGroups[0].alias, 'GROUP_A');
    expect(decoded.effectiveKeyGroups[1].alias, 'GROUP_B');
    expect(decoded.effectiveApiKeys, <String>['KEY_A', 'KEY_B']);
  });

  test('duplicate key is never assigned to two quota groups', () {
    final groups = GeminiInvoiceSettings.parseKeyGroups(
      'KEY_A，KEY_SHARED\nKEY_SHARED，KEY_B',
    );
    expect(groups, hasLength(2));
    expect(groups[0].apiKeys, <String>['KEY_A', 'KEY_SHARED']);
    expect(groups[1].apiKeys, <String>['KEY_B']);
  });
}
