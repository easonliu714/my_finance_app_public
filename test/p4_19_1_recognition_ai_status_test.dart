import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/recognition_ai/recognition_ai_contract.dart';
import 'package:my_finance_app/features/recognition_ai/recognition_ai_status_indicator.dart';

void main() {
  const session = RecognitionSessionContext(
    logicalInvocationId: 'logical-1',
    provider: 'Gemini',
    activeModel: 'provider-listed-flash',
    keyGroupAlias: 'GROUP_B',
    logicalInvocationCount: 1,
    physicalAttemptCount: 2,
    modelAttemptCount: 1,
    keyGroupAttemptCount: 2,
    fallbackReason: RecognitionAiFallbackReason.quotaExhausted,
    modelCatalogChecked: true,
  );

  testWidgets('status shows active model and fallback without raw key', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecognitionAiStatusIndicator(context: session),
        ),
      ),
    );

    expect(find.textContaining('Gemini'), findsOneWidget);
    expect(find.textContaining('provider-listed-flash'), findsOneWidget);
    expect(find.text('配額已滿，已切換 Key Group'), findsOneWidget);
    expect(find.textContaining('AIza'), findsNothing);
    expect(find.textContaining('GROUP_B'), findsNothing);
  });

  test('safe JSON includes routing metadata but no credential field', () {
    final json = session.toSafeJson();
    expect(json['active_model'], 'provider-listed-flash');
    expect(json['key_group_alias'], 'GROUP_B');
    expect(json['physical_attempt_count'], 2);
    expect(json['fallback_reason'], 'quotaExhausted');
    expect(json.keys, isNot(contains('api_key')));
    expect(json.keys, isNot(contains('apiKey')));
  });
}
