import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_event_record.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/account_store.dart';
import 'package:my_finance_app/features/invoice/manual_invoice_draft.dart';
import 'package:my_finance_app/features/invoice/manual_invoice_draft_repository.dart';
import 'package:my_finance_app/features/invoice/manual_invoice_entry_page.dart';
import 'package:my_finance_app/features/invoice/manual_invoice_service.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_store.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  testWidgets('ManualInvoiceEntryPage renders local-first invoice form', (tester) async {
    await _pumpManualInvoiceEntryPage(tester);

    expect(find.text('手動輸入發票'), findsOneWidget);
    expect(find.text('發票資料'), findsOneWidget);
    expect(find.textContaining('不串接財政部 API'), findsOneWidget);
    expect(find.byKey(ManualInvoiceEntryPage.invoiceNumberFieldKey), findsOneWidget);
    expect(find.text('正式交易需為 AB12345678 格式；格式不符可先存草稿，不能建立交易。'), findsOneWidget);
    expect(find.byKey(ManualInvoiceEntryPage.sellerNameFieldKey), findsOneWidget);
    expect(find.byKey(ManualInvoiceEntryPage.addMerchantButtonKey), findsOneWidget);
    expect(find.byKey(ManualInvoiceEntryPage.totalAmountFieldKey), findsOneWidget);
    expect(find.byKey(ManualInvoiceEntryPage.taxAmountFieldKey), findsOneWidget);
    expect(find.byKey(ManualInvoiceEntryPage.paymentAccountFieldKey), findsOneWidget);
    expect(find.text('現金'), findsOneWidget);
    expect(find.byKey(ManualInvoiceEntryPage.noteFieldKey), findsOneWidget);
    expect(find.byKey(ManualInvoiceEntryPage.saveDraftButtonKey), findsOneWidget);
    expect(find.text('2026-06-09'), findsOneWidget);
  });

  testWidgets('ManualInvoiceEntryPage shows validation errors for required fields', (tester) async {
    await _pumpManualInvoiceEntryPage(tester);

    final reviewButton = find.byKey(ManualInvoiceEntryPage.reviewButtonKey);
    await tester.ensureVisible(reviewButton);
    await tester.tap(reviewButton);
    await tester.pumpAndSettle();

    expect(find.text('請先修正以下欄位'), findsOneWidget);
    expect(find.text('• 請輸入發票號碼'), findsOneWidget);
    expect(find.text('• 請輸入店家名稱'), findsOneWidget);
    expect(find.text('• 請選擇店家'), findsOneWidget);
    expect(find.text('• 發票總額必須大於 0'), findsOneWidget);
    expect(find.text('• 請選擇付款帳戶'), findsNothing);
  });

  testWidgets('ManualInvoiceEntryPage blocks invalid invoice format before formal transaction preview', (tester) async {
    final store = InMemoryTransactionStore();
    await _pumpManualInvoiceEntryPage(tester, transactionStore: store);

    await tester.enterText(find.byKey(ManualInvoiceEntryPage.invoiceNumberFieldKey), 'bad-format');
    await _selectMerchant(tester, '測試便利商店');
    await tester.enterText(find.byKey(ManualInvoiceEntryPage.totalAmountFieldKey), '120');
    final reviewButton = find.byKey(ManualInvoiceEntryPage.reviewButtonKey);
    await tester.ensureVisible(reviewButton);
    await tester.tap(reviewButton);
    await tester.pumpAndSettle();

    expect(find.text('請先修正以下欄位'), findsOneWidget);
    expect(find.text('• $manualInvoiceNumberFormatError'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('確認建立正式交易'), findsNothing);
    expect(await store.listRecent(), isEmpty);
  });

  testWidgets('ManualInvoiceEntryPage saves invalid invoice format as local draft warning', (tester) async {
    final repository = InMemoryManualInvoiceDraftRepository(clock: () => DateTime.utc(2026, 6, 9, 8, 0));
    await _pumpManualInvoiceEntryPage(tester, repository: repository);

    await tester.enterText(find.byKey(ManualInvoiceEntryPage.invoiceNumberFieldKey), 'bad-format');
    await _selectMerchant(tester, '測試便利商店');
    await tester.enterText(find.byKey(ManualInvoiceEntryPage.totalAmountFieldKey), '120');
    final saveButton = find.byKey(ManualInvoiceEntryPage.saveDraftButtonKey);
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final drafts = await repository.loadDrafts(status: ManualInvoiceDraftStatus.readyToReview);
    expect(drafts, hasLength(1));
    expect(drafts.single.invoiceNumber, 'bad-format');
    expect(find.text('• $manualInvoiceNumberFormatWarning'), findsOneWidget);
    expect(find.text('已儲存本機發票草稿：BAD-FORMAT'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('ManualInvoiceEntryPage saves valid invoice draft explicitly', (tester) async {
    final repository = InMemoryManualInvoiceDraftRepository(clock: () => DateTime.utc(2026, 6, 9, 8, 0));
    await _pumpManualInvoiceEntryPage(tester, repository: repository);

    await _enterValidInvoice(tester);
    final saveButton = find.byKey(ManualInvoiceEntryPage.saveDraftButtonKey);
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final drafts = await repository.loadDrafts(status: ManualInvoiceDraftStatus.readyToReview);
    expect(drafts, hasLength(1));
    expect(drafts.single.invoiceNumber, 'AB12345678');
    expect(drafts.single.sellerName, '測試便利商店');
    expect(find.text('已儲存本機發票草稿：AB12345678'), findsOneWidget);
  });

  testWidgets('ManualInvoiceEntryPage surfaces duplicate draft feedback without overwrite', (tester) async {
    final repository = InMemoryManualInvoiceDraftRepository(clock: () => DateTime.utc(2026, 6, 9, 8, 0));
    await repository.saveDraft(
      ManualInvoiceDraft(
        id: 'existing-draft',
        invoiceNumber: 'AB12345678',
        invoiceDate: DateTime(2026, 6, 9),
        sellerName: '測試便利商店',
        totalAmount: 120,
        status: ManualInvoiceDraftStatus.readyToReview,
      ),
    );
    await _pumpManualInvoiceEntryPage(tester, repository: repository);

    await tester.enterText(find.byKey(ManualInvoiceEntryPage.invoiceNumberFieldKey), 'AB12345678');
    await _selectMerchant(tester, '測試便利商店');
    await tester.enterText(find.byKey(ManualInvoiceEntryPage.totalAmountFieldKey), '120');
    final saveButton = find.byKey(ManualInvoiceEntryPage.saveDraftButtonKey);
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final drafts = await repository.loadDrafts(status: ManualInvoiceDraftStatus.readyToReview);
    expect(drafts, hasLength(1));
    expect(drafts.single.id, 'existing-draft');
    expect(find.text('此發票已存在本機草稿，未覆蓋既有資料'), findsOneWidget);
  });

  testWidgets('ManualInvoiceEntryPage opens review dialog before writing transaction', (tester) async {
    final store = InMemoryTransactionStore();
    await _pumpManualInvoiceEntryPage(tester, transactionStore: store);

    await _enterValidInvoice(tester);
    final reviewButton = find.byKey(ManualInvoiceEntryPage.reviewButtonKey);
    await tester.ensureVisible(reviewButton);
    await tester.tap(reviewButton);
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('發票轉交易預覽')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('AB12345678')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('測試便利商店')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('現金')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('NT\$ 120')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('發票：AB12345678｜早餐')), findsOneWidget);
    expect(await store.listRecent(), isEmpty);
  });

  testWidgets('ManualInvoiceEntryPage selects merchant from existing options', (tester) async {
    final store = InMemoryTransactionStore();
    await _pumpManualInvoiceEntryPage(tester, transactionStore: store, merchantOptions: const ['小七', '測試便利商店']);

    await _selectMerchant(tester, '小七');
    await tester.enterText(find.byKey(ManualInvoiceEntryPage.invoiceNumberFieldKey), 'AC87654321');
    await tester.enterText(find.byKey(ManualInvoiceEntryPage.totalAmountFieldKey), '99');
    final reviewButton = find.byKey(ManualInvoiceEntryPage.reviewButtonKey);
    await tester.ensureVisible(reviewButton);
    await tester.tap(reviewButton);
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('小七')), findsOneWidget);
    await tester.tap(find.text('確認建立正式交易'));
    await tester.pumpAndSettle();

    final records = await store.listRecent();
    expect(records, hasLength(1));
    expect(records.single.merchantName, '小七');
  });

  testWidgets('ManualInvoiceEntryPage opens explicit add merchant sheet', (tester) async {
    await _pumpManualInvoiceEntryPage(tester, merchantOptions: const ['小七', '測試便利商店']);

    await tester.tap(find.byKey(ManualInvoiceEntryPage.addMerchantButtonKey));
    await tester.pumpAndSettle();

    expect(find.textContaining('新增後會保存至本機商家主檔'), findsOneWidget);
    expect(find.byKey(ManualInvoiceEntryPage.addMerchantNameFieldKey), findsOneWidget);
    expect(find.byKey(ManualInvoiceEntryPage.confirmAddMerchantButtonKey), findsOneWidget);
  });

  testWidgets('ManualInvoiceEntryPage selects payment account from real local accounts', (tester) async {
    final store = InMemoryTransactionStore();
    await _pumpManualInvoiceEntryPage(tester, transactionStore: store);

    await tester.tap(find.byKey(ManualInvoiceEntryPage.paymentAccountFieldKey));
    await tester.pumpAndSettle();
    expect(find.text('銀行・薪轉'), findsWidgets);
    expect(find.text('房貸'), findsNothing);
    await tester.tap(find.text('銀行・薪轉').last);
    await tester.pumpAndSettle();

    await _enterValidInvoice(tester);
    final reviewButton = find.byKey(ManualInvoiceEntryPage.reviewButtonKey);
    await tester.ensureVisible(reviewButton);
    await tester.tap(reviewButton);
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('銀行・薪轉')), findsOneWidget);
    await tester.tap(find.text('確認建立正式交易'));
    await tester.pumpAndSettle();

    final records = await store.listRecent();
    expect(records, hasLength(1));
    expect(records.single.accountName, '銀行・薪轉');
  });

  testWidgets('ManualInvoiceEntryPage cancel review does not write transaction', (tester) async {
    final store = InMemoryTransactionStore();
    await _pumpManualInvoiceEntryPage(tester, transactionStore: store);

    await _enterValidInvoice(tester);
    final reviewButton = find.byKey(ManualInvoiceEntryPage.reviewButtonKey);
    await tester.ensureVisible(reviewButton);
    await tester.tap(reviewButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('返回修改'));
    await tester.pumpAndSettle();

    expect(await store.listRecent(), isEmpty);
  });

  testWidgets('ManualInvoiceEntryPage confirms and writes one formal expense transaction', (tester) async {
    final store = InMemoryTransactionStore();
    await _pumpManualInvoiceEntryPage(tester, transactionStore: store);

    await _enterValidInvoice(tester);
    final reviewButton = find.byKey(ManualInvoiceEntryPage.reviewButtonKey);
    await tester.ensureVisible(reviewButton);
    await tester.tap(reviewButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('確認建立正式交易'));
    await tester.pumpAndSettle();

    final records = await store.listRecent();
    expect(records, hasLength(1));
    expect(records.single.type, TransactionType.expense);
    expect(records.single.amount, 120);
    expect(records.single.accountName, '現金');
    expect(records.single.merchantName, '測試便利商店');
    expect(records.single.note, '發票：AB12345678｜早餐');
    expect(find.text('已建立正式支出交易'), findsOneWidget);
  });
}

Future<void> _pumpManualInvoiceEntryPage(
  WidgetTester tester, {
  ManualInvoiceDraftRepository? repository,
  TransactionStore? transactionStore,
  AccountStore? accountStore,
  List<String>? merchantOptions,
  DateTime? initialInvoiceDate,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: ManualInvoiceEntryPage(
          initialInvoiceDate: initialInvoiceDate ?? DateTime(2026, 6, 9),
          repository: repository,
          transactionStore: transactionStore,
          accountStore: accountStore ?? _testAccountStore(),
          merchantOptions: merchantOptions ?? const ['測試便利商店'],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

_TestAccountStore _testAccountStore() => _TestAccountStore(const [
      AccountRecord(
        id: 'cash-1',
        name: '現金',
        type: AccountType.cash,
        initialBalance: 0,
        sortOrder: 10,
      ),
      AccountRecord(
        id: 'bank-1',
        name: '銀行',
        suffix: '薪轉',
        type: AccountType.bank,
        initialBalance: 0,
        sortOrder: 20,
      ),
      AccountRecord(
        id: 'loan-1',
        name: '房貸',
        type: AccountType.loan,
        initialBalance: 0,
        sortOrder: 30,
      ),
    ]);

Future<void> _enterValidInvoice(WidgetTester tester) async {
  await tester.enterText(find.byKey(ManualInvoiceEntryPage.invoiceNumberFieldKey), 'AB12345678');
  await _selectMerchant(tester, '測試便利商店');
  await tester.enterText(find.byKey(ManualInvoiceEntryPage.totalAmountFieldKey), '120');
  await tester.enterText(find.byKey(ManualInvoiceEntryPage.taxAmountFieldKey), '6');
  await tester.enterText(find.byKey(ManualInvoiceEntryPage.noteFieldKey), '早餐');
}

Future<void> _selectMerchant(WidgetTester tester, String merchant) async {
  await tester.tap(find.byKey(ManualInvoiceEntryPage.sellerNameFieldKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(merchant).last);
  await tester.pumpAndSettle();
}

class _TestAccountStore extends AccountStore {
  _TestAccountStore(this.accounts);

  final List<AccountRecord> accounts;

  @override
  Future<List<AccountRecord>> listAccounts({bool includeArchived = false}) async {
    return accounts.where((account) => includeArchived || !account.isArchived).toList();
  }

  @override
  Future<void> upsertAccount(AccountRecord account) async {}

  @override
  Future<void> archiveAccount(String id) async {}

  @override
  Future<List<AccountEventRecord>> listAccountEvents(String accountName) async => const [];

  @override
  Future<List<TransactionRecord>> listAccountTransactions(String accountName) async => const [];

  @override
  Future<void> upsertAccountEvent(AccountEventRecord event) async {}

  @override
  Future<void> deleteAccountEvent(String id) async {}
}

class InMemoryTransactionStore implements TransactionStore {
  final List<TransactionRecord> records = <TransactionRecord>[];

  @override
  Future<void> insert(TransactionRecord record) async {
    records.add(record);
  }

  @override
  Future<void> update(TransactionRecord record) async {}

  @override
  Future<void> deleteById(String id) async {}

  @override
  Future<void> deleteByRepaymentGroupId(String repaymentGroupId) async {}

  @override
  Future<void> deleteLoanRepaymentCluster(TransactionRecord record) async {}

  @override
  Future<List<TransactionRecord>> listRecent({int limit = 50}) async {
    return records.take(limit).toList(growable: false);
  }

  @override
  Future<double> monthlyIncome(DateTime month) async => 0;

  @override
  Future<double> monthlyExpense(DateTime month) async => records.fold<double>(0, (sum, record) => record.type == TransactionType.expense ? sum + record.amount : sum);
}
