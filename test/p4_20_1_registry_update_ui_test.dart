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

  testWidgets('registry update card queries complete official fields locally',
      (tester) async {
    final snapshot = BusinessRegistrySnapshotInfo(
      version: '2026-09-08',
      sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
      sourceDataDate: '2026-09-08',
      contentSha256: 'd' * 64,
      coverage: BusinessRegistryPack.nationwideCoverage,
      installedAt: DateTime.utc(2026, 9, 8),
    );
    var lookups = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BusinessRegistryUpdateCard(
              snapshot: snapshot,
              loading: false,
              updating: false,
              distributionConfigured: true,
              statusMessage: '',
              onRefresh: () {},
              onLookupOfficialDetail: (seller) async {
                lookups += 1;
                expect(seller, '31655572');
                return const BusinessRegistryOfficialDetailLookupResult(
                  status: BusinessRegistryOfficialDetailLookupStatus.hit,
                  snapshotVersion: '2026-09-08',
                  sourceDataDate: '2026-09-08',
                  fields: <String, String>{
                    '營業地址': '新北市土城區測試路1號',
                    '統一編號': '31655572',
                    '總機構統一編號': '22853565',
                    '營業人名稱': '富達零售股份有限公司晶技門市',
                    '資本額': '1000000',
                    '設立日期': '20200101',
                    '組織別名稱': '其他',
                    '使用統一發票': 'Y',
                    '行業代號': '471112',
                    '名稱': '直營連鎖式便利商店',
                    '行業代號1': '',
                    '名稱1': '',
                    '行業代號2': '',
                    '名稱2': '',
                    '行業代號3': '',
                    '名稱3': '',
                  },
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('用統編查詢完整官方資料'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(BusinessRegistryOfficialDetailLookupPanel.sellerFieldKey),
      '31655572',
    );
    await tester.tap(
      find.byKey(BusinessRegistryOfficialDetailLookupPanel.lookupKey),
    );
    await tester.pumpAndSettle();

    expect(lookups, 1);
    expect(
      find.byKey(BusinessRegistryOfficialDetailLookupPanel.resultKey),
      findsOneWidget,
    );
    expect(find.text('富達零售股份有限公司晶技門市'), findsOneWidget);
    expect(find.text('新北市土城區測試路1號'), findsOneWidget);
    expect(find.text('471112'), findsOneWidget);
    expect(find.textContaining('不會寫入記帳明細'), findsOneWidget);
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
      find.byKey(BusinessRegistryUpdateCard.refreshKey),
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

  testWidgets(
      'failed update preserves last-known-good status and keeps explicit retry available',
      (tester) async {
    final snapshot = BusinessRegistrySnapshotInfo(
      version: '2026-08-31',
      sourceDataset: 'nationwide_company_business_branch',
      sourceDataDate: '2026-08-31',
      contentSha256: 'c' * 64,
      coverage: BusinessRegistryPack.nationwideCoverage,
      installedAt: DateTime.utc(2026, 8, 31),
    );
    var retries = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessRegistryUpdateCard(
            snapshot: snapshot,
            loading: false,
            updating: false,
            distributionConfigured: true,
            statusMessage: '更新失敗，已保留上一版公司行號資料。',
            onRefresh: () => retries += 1,
          ),
        ),
      ),
    );

    expect(find.text('2026-08-31'), findsNWidgets(2));
    expect(find.text('全台公司／商業／分公司'), findsOneWidget);
    expect(
      find.byKey(BusinessRegistryUpdateCard.statusKey),
      findsOneWidget,
    );
    expect(find.textContaining('已保留上一版公司行號資料'), findsOneWidget);

    final button = tester.widget<FilledButton>(
      find.byKey(BusinessRegistryUpdateCard.refreshKey),
    );
    expect(button.onPressed, isNotNull);

    await tester.tap(find.byKey(BusinessRegistryUpdateCard.refreshKey));
    await tester.pump();
    expect(retries, 1);
  });
}
