import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/draft_storage_hidden_route_page.dart';
import 'package:my_finance_app/features/invoice/draft_storage_ui_gate.dart';
import 'package:my_finance_app/features/invoice/draft_storage_ui_gate_card.dart';
import 'package:my_finance_app/routing/app_router.dart';

void main() {
  test('hidden draft storage route metadata is deterministic', () {
    expect(DraftStorageHiddenRoutePage.routePath, '/_internal/draft-storage-placeholder');
    expect(DraftStorageHiddenRoutePage.routeName, 'draft-storage-placeholder');
    expect(DraftStorageHiddenRoutePage.isVisibleNavigationEntry, isFalse);
    expect(appRouter.namedLocation(DraftStorageHiddenRoutePage.routeName), DraftStorageHiddenRoutePage.routePath);
  });

  testWidgets('hidden route page renders disabled placeholder by default', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DraftStorageHiddenRoutePage()),
    );

    expect(find.byType(DraftStorageHiddenRoutePage), findsOneWidget);
    expect(find.byKey(DraftStorageUiGateCard.cardKey), findsOneWidget);
    expect(find.byKey(DraftStorageUiGateCard.hiddenStateKey), findsOneWidget);
    expect(find.text('Hidden'), findsOneWidget);
    final page = tester.widget<DraftStorageHiddenRoutePage>(find.byType(DraftStorageHiddenRoutePage));
    expect(page.canShowVisibleNavigationEntry, isFalse);
    expect(page.canRunLiveUiAction, isFalse);
    expect(page.canMutateRuntimeStorage, isFalse);
    expect(page.canCreateFinalRecordAutomatically, isFalse);
    expect(page.requiresManualApkValidation, isFalse);
  });

  testWidgets('hidden route page shows APK notice for live intent while actions stay disabled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DraftStorageHiddenRoutePage(config: DraftStorageUiGateConfig(liveUiIntent: true)),
      ),
    );

    expect(find.byKey(DraftStorageUiGateCard.apkNoticeKey), findsOneWidget);
    expect(find.textContaining('APK validation is required'), findsOneWidget);
    final page = tester.widget<DraftStorageHiddenRoutePage>(find.byType(DraftStorageHiddenRoutePage));
    expect(page.requiresManualApkValidation, isTrue);
    expect(tester.widget<OutlinedButton>(find.byKey(DraftStorageUiGateCard.openActionKey)).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.byKey(DraftStorageUiGateCard.writeActionKey)).onPressed, isNull);
  });
}
