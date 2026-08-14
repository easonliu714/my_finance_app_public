import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/draft_storage_ui_gate.dart';
import 'package:my_finance_app/features/invoice/draft_storage_ui_gate_card.dart';

void main() {
  testWidgets('card renders hidden state by default', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DraftStorageUiGateCard())),
    );

    expect(find.byKey(DraftStorageUiGateCard.cardKey), findsOneWidget);
    expect(find.byKey(DraftStorageUiGateCard.hiddenStateKey), findsOneWidget);
    expect(find.text('Hidden'), findsOneWidget);
    expect(find.textContaining('no manual APK validation is required yet'), findsOneWidget);
    expect(tester.widget<DraftStorageUiGateCard>(find.byType(DraftStorageUiGateCard)).canShowLiveUiAction, isFalse);
    expect(tester.widget<DraftStorageUiGateCard>(find.byType(DraftStorageUiGateCard)).canMutateRuntimeStorage, isFalse);
    expect(tester.widget<DraftStorageUiGateCard>(find.byType(DraftStorageUiGateCard)).canCreateFinalRecordAutomatically, isFalse);
  });

  testWidgets('card renders APK notice when live UI intent appears', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DraftStorageUiGateCard(config: DraftStorageUiGateConfig(liveUiIntent: true)),
        ),
      ),
    );

    expect(find.byKey(DraftStorageUiGateCard.apkNoticeKey), findsOneWidget);
    expect(find.textContaining('APK validation is required'), findsOneWidget);
    expect(find.text('Hidden'), findsOneWidget);
  });

  testWidgets('card keeps placeholder actions disabled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DraftStorageUiGateCard())),
    );

    expect(find.byKey(DraftStorageUiGateCard.openActionKey), findsOneWidget);
    expect(find.byKey(DraftStorageUiGateCard.writeActionKey), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(DraftStorageUiGateCard.openActionKey)).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.byKey(DraftStorageUiGateCard.writeActionKey)).onPressed, isNull);
  });
}
