import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';
import 'package:my_finance_app/features/merchant/business_registry_repository.dart';
import 'package:my_finance_app/features/profile/business_registry_update_card.dart';

void main() {
  testWidgets(
      'registry update card shows installed version date nationwide coverage and explicit update action',
      (tester) async {
    final snapshot = BusinessRegistrySnapshotInfo(
      version: '2026-09-01',
      sourceDataset: 'nationwide_company_business_branch',
      sourceDataDate: '2026-09-01',
      contentSha256: 'a' * 64,
      coverage: BusinessRegistryPack.nationwideCoverage,
      installedAt: DateTime.utc(2026, 9, 1),
    );
    var refreshes = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessRegistryUpdateCard(
            snapshot: snapshot,
            loading: false,
            updating: false,
            distributionConfigured: true,
            statusMessage: '',
            onRefresh: () => refreshes += 1,
          ),
        ),
      ),
    );

    expect(
      find.byKey(BusinessRegistryUpdateCard.versionKey),
      findsOneWidget,
    );
    expect(find.text('2026-09-01'), findsNWidgets(2));
    expect(find.text('全台公司／商業／分公司'), findsOneWidget);
    expect(find.text('來源：nationwide_company_business_branch'), findsOneWidget);
    expect(find.text('更新公司行號資料'), findsOneWidget);

    await tester.tap(find.byKey(BusinessRegistryUpdateCard.refreshKey));
    await tester.pump();
    expect(refreshes, 1);
  });

  testWidgets('validation subset is never presented as nationwide',
      (tester) async {
    final snapshot = BusinessRegistrySnapshotInfo(
      version: 'p4.20-validation',
      sourceDataset: 'signed_canary_subset',
      sourceDataDate: '2026-08-31',
      contentSha256: 'b' * 64,
      coverage: BusinessRegistryPack.validationSubsetCoverage,
      installedAt: DateTime.utc(2026, 8, 31),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessRegistryUpdateCard(
            snapshot: snapshot,
            loading: false,
            updating: false,
            distributionConfigured: false,
            statusMessage: '',
            onRefresh: null,
          ),
        ),
      ),
    );

    expect(find.text('實機驗證子集'), findsOneWidget);
    expect(find.text('全台公司／商業／分公司'), findsNothing);
  });

  testWidgets('unconfigured distribution disables update but preserves offline status',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BusinessRegistryUpdateCard(
            snapshot: null,
            loading: false,
            updating: false,
            distributionConfigured: false,
            statusMessage: '',
            onRefresh: null,
          ),
        ),
      ),
    );

    expect(find.text('尚未安裝'), findsOneWidget);
    expect(
      find.textContaining('尚未設定公司行號資料發布端點'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(BusinessRegistryUpdateCard.refreshKey),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('update in progress disables repeated update action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BusinessRegistryUpdateCard(
            snapshot: null,
            loading: false,
            updating: true,
            distributionConfigured: true,
            statusMessage: '正在下載並驗證公司行號資料…',
            onRefresh: null,
          ),
        ),
      ),
    );

    expect(find.text('正在更新公司行號資料…'), findsOneWidget);
    expect(find.text('正在下載並驗證公司行號資料…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
