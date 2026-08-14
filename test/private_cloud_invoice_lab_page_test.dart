import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_persistence_models.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_lab_page.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_lab_smoke_service.dart';

void main() {
  testWidgets('empty account list offers existing account page navigation', (
    tester,
  ) async {
    final port = _FakeSmokePort(accounts: const <AccountRecord>[]);
    var openedAccounts = false;
    await _pumpLab(
      tester,
      PrivateCloudInvoiceLabPage(
        smokePort: port,
        onOpenAccounts: () => openedAccounts = true,
        onOpenWebView: () {},
        onOpenCsvImport: () {},
      ),
    );

    expect(find.text('目前沒有可使用的有效帳戶。'), findsOneWidget);
    await tester.tap(
      find.byKey(PrivateCloudInvoiceLabPage.accountButtonKey),
    );
    expect(openedAccounts, isTrue);
    expect(port.executeCalls, 0);
  });

  testWidgets('smoke validation requires account selection and confirmation', (
    tester,
  ) async {
    final account = _account();
    final port = _FakeSmokePort(accounts: <AccountRecord>[account]);
    await _pumpLab(
      tester,
      PrivateCloudInvoiceLabPage(
        smokePort: port,
        onOpenAccounts: () {},
        onOpenWebView: () {},
        onOpenCsvImport: () {},
      ),
    );

    final runFinder = find.byKey(PrivateCloudInvoiceLabPage.runButtonKey);
    var runButton = tester.widget<FilledButton>(runFinder);
    expect(runButton.onPressed, isNull);

    await tester.tap(
      find.byKey(PrivateCloudInvoiceLabPage.accountDropdownKey),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('現金・TWD').last);
    await tester.pumpAndSettle();

    runButton = tester.widget<FilledButton>(runFinder);
    expect(runButton.onPressed, isNull);

    await tester.tap(find.byKey(PrivateCloudInvoiceLabPage.consentKey));
    await tester.pumpAndSettle();
    runButton = tester.widget<FilledButton>(runFinder);
    expect(runButton.onPressed, isNotNull);

    await tester.tap(runFinder);
    await tester.pumpAndSettle();

    expect(port.executeCalls, 1);
    expect(port.lastAccountId, account.id);
    expect(find.byKey(PrivateCloudInvoiceLabPage.resultKey), findsOneWidget);
    expect(find.textContaining('正式交易筆數未改變'), findsOneWidget);

    await tester.tap(
      find.byKey(PrivateCloudInvoiceLabPage.cleanupButtonKey),
    );
    await tester.pumpAndSettle();
    expect(port.cleanupCalls, 1);
    expect(find.textContaining('已清理 3 筆 LAB 驗證資料'), findsOneWidget);
  });

  testWidgets('WebView launch remains an explicit button action', (
    tester,
  ) async {
    final port = _FakeSmokePort(accounts: <AccountRecord>[_account()]);
    var opened = false;
    await _pumpLab(
      tester,
      PrivateCloudInvoiceLabPage(
        smokePort: port,
        onOpenAccounts: () {},
        onOpenWebView: () => opened = true,
        onOpenCsvImport: () {},
      ),
    );

    expect(opened, isFalse);
    await tester.tap(
      find.byKey(PrivateCloudInvoiceLabPage.webViewButtonKey),
    );
    expect(opened, isTrue);
  });

  testWidgets('CSV import launch remains an explicit button action', (
    tester,
  ) async {
    final port = _FakeSmokePort(accounts: <AccountRecord>[_account()]);
    var opened = false;
    await _pumpLab(
      tester,
      PrivateCloudInvoiceLabPage(
        smokePort: port,
        onOpenAccounts: () {},
        onOpenWebView: () {},
        onOpenCsvImport: () => opened = true,
      ),
    );

    expect(opened, isFalse);
    await tester.tap(
      find.byKey(PrivateCloudInvoiceLabPage.csvImportButtonKey),
    );
    expect(opened, isTrue);
  });
}

Future<void> _pumpLab(
  WidgetTester tester,
  Widget page,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pumpAndSettle();
}

AccountRecord _account() {
  return const AccountRecord(
    id: 'account-1',
    name: '現金',
    type: AccountType.cash,
    initialBalance: 0,
    sortOrder: 0,
  );
}

class _FakeSmokePort implements PrivateCloudInvoiceLabSmokePort {
  _FakeSmokePort({required this.accounts});

  final List<AccountRecord> accounts;
  int executeCalls = 0;
  int cleanupCalls = 0;
  String? lastAccountId;

  @override
  Future<List<AccountRecord>> listActiveAccounts() async => accounts;

  @override
  Future<PrivateCloudInvoiceLabSmokeSnapshot> execute(
    AccountRecord account,
  ) async {
    executeCalls += 1;
    lastAccountId = account.id;
    return const PrivateCloudInvoiceLabSmokeSnapshot(
      status: CloudInvoicePersistenceStatus.committed,
      operationKey: 'cloud-invoice:PRIVATE-LAB-SMOKE-V1:createNewDraft',
      message: 'DRAFT_CREATED',
      draftId: 'draft-1',
      draftCount: 1,
      operationCount: 1,
      auditCount: 1,
      transactionCountUnchanged: true,
    );
  }

  @override
  Future<PrivateCloudInvoiceLabCleanupResult> cleanup(
    AccountRecord account,
  ) async {
    cleanupCalls += 1;
    lastAccountId = account.id;
    return const PrivateCloudInvoiceLabCleanupResult(
      deletedDrafts: 1,
      deletedLinks: 0,
      deletedBeforeImages: 0,
      deletedAudits: 1,
      deletedOperations: 1,
    );
  }
}
