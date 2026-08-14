import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/ai_model_entry_rotation.dart';
import 'package:my_finance_app/features/invoice/ai_model_settings_card.dart';

void main() {
  testWidgets('AiModelSettingsCard shows safe empty state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiModelSettingsCard(),
        ),
      ),
    );

    expect(find.byKey(AiModelSettingsCard.cardKey), findsOneWidget);
    expect(find.text('AI 模型設定'), findsOneWidget);
    expect(find.text('目前模型：Gemini Flash latest'), findsOneWidget);
    expect(find.byKey(AiModelSettingsCard.activeEntryKey), findsOneWidget);
    expect(find.text('目前項目：尚未設定'), findsOneWidget);
    expect(find.text('狀態：尚未設定'), findsOneWidget);
    expect(find.text('備援狀態：尚無可切換項目'), findsOneWidget);
  });

  testWidgets('AiModelSettingsCard shows active usable entry and fallback summary', (tester) async {
    const state = AiModelEntryRotationState(
      entries: <AiModelEntry>[
        AiModelEntry(id: 'entry-a', maskedLabel: '••••0001', status: AiModelEntryStatus.rejected),
        AiModelEntry(id: 'entry-b', maskedLabel: '••••0002', status: AiModelEntryStatus.usable),
        AiModelEntry(id: 'entry-c', maskedLabel: '••••0003', status: AiModelEntryStatus.unknown),
      ],
      lastSuccessfulEntryId: 'entry-b',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiModelSettingsCard(rotationState: state),
        ),
      ),
    );

    expect(find.text('可用'), findsAtLeastNWidgets(1));
    expect(find.text('目前項目：••••0002'), findsOneWidget);
    expect(find.text('狀態：可用'), findsOneWidget);
    expect(find.text('備援狀態：2/3 可用，1 個已跳過'), findsOneWidget);
  });

  testWidgets('AiModelSettingsCard shows no active entry when all entries are unavailable', (tester) async {
    const state = AiModelEntryRotationState(
      entries: <AiModelEntry>[
        AiModelEntry(id: 'entry-a', maskedLabel: '••••0001', status: AiModelEntryStatus.rejected),
        AiModelEntry(id: 'entry-b', maskedLabel: '••••0002', status: AiModelEntryStatus.quotaExhausted),
        AiModelEntry(id: 'entry-c', maskedLabel: '••••0003', status: AiModelEntryStatus.disabled),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiModelSettingsCard(rotationState: state),
        ),
      ),
    );

    expect(find.text('待設定'), findsOneWidget);
    expect(find.text('目前項目：尚未設定'), findsOneWidget);
    expect(find.text('狀態：尚未設定'), findsOneWidget);
    expect(find.text('備援狀態：目前沒有可用項目'), findsOneWidget);
  });
}
