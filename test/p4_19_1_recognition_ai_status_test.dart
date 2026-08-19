import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/recognition_ai/recognition_ai_contract.dart';
import 'package:my_finance_app/features/recognition_ai/recognition_ai_status_indicator.dart';

void main() {
  const session = RecognitionSessionContext(
    logicalInvocationId: 'logical-1',
    provider: 'Gemini',
    activeModel: 'provider-listed-flash',
    keyGroupAlias: 'KEY_2',
    logicalInvocationCount: 1,
    physicalAttemptCount: 2,
    modelAttemptCount: 1,
    keyGroupAttemptCount: 2,
    fallbackReason: RecognitionAiFallbackReason.quotaExhausted,
    modelCatalogChecked: true,
  );

  testWidgets('running status shows active model and elapsed time', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecognitionAiRunningStatusIndicator(
            provider: 'Gemini',
            activeModel: 'gemini-3.6-flash',
            elapsed: Duration(seconds: 17),
            message: '正在辨識…',
          ),
        ),
      ),
    );

    expect(find.textContaining('Gemini · gemini-3.6-flash'), findsOneWidget);
    expect(find.textContaining('已等待 17 秒'), findsOneWidget);
    expect(find.textContaining('正在辨識'), findsOneWidget);
    expect(find.textContaining('AIza'), findsNothing);
  });

  testWidgets('completed status shows active model and key fallback safely', (
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
    expect(find.text('配額已滿，已切換下一組 API Key'), findsOneWidget);
    expect(find.textContaining('AIza'), findsNothing);
    expect(find.textContaining('KEY_2'), findsNothing);
  });

  test('safe JSON includes routing metadata but no credential field', () {
    final json = session.toSafeJson();
    expect(json['active_model'], 'provider-listed-flash');
    expect(json['key_group_alias'], 'KEY_2');
    expect(json['physical_attempt_count'], 2);
    expect(json['fallback_reason'], 'quotaExhausted');
    expect(json.keys, isNot(contains('api_key')));
    expect(json.keys, isNot(contains('apiKey')));
  });
}
