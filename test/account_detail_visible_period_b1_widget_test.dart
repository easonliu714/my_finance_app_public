import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_detail_page.dart';
import 'package:my_finance_app/features/account/account_event_record.dart';
import 'package:my_finance_app/features/account/account_providers.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/account_store.dart';
import 'package:my_finance_app/features/account/debit_card_available_balance_providers.dart';
import 'package:my_finance_app/features/account/debit_card_settlement_providers.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_repository.dart';
import 'package:my_finance_app/features/transaction/transaction_providers.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_store.dart';

void main() {
  test('B1 summaryFor is period-bound and leaves the running balance unchanged', () {
    const account = AccountRecord(
      id: 'summary', name: 'Synthetic', type: AccountType.eWallet,
      initialBalance: 0, sortOrder: 0,
    );
    final state = AccountDetailState(account: account, items: [
      AccountLedgerItem(
        id: 'dec', title: 'December', subtitle: '',
        occurredAt: DateTime(2026, 12, 31), amountForAccount: -56,
        runningBalance: -56,
      ),
      AccountLedgerItem(
        id: 'jan', title: 'January', subtitle: '',
        occurredAt: DateTime(2027, 1, 1), amountForAccount: 10,
        runningBalance: -46,
      ),
    ]);
    expect(state.summaryFor(year: 2026, label: '2026').net, -56);
    expect(state.summaryFor(year: 2026, month: 12, label: '12').outflow, 56);
    expect(state.summaryFor(year: 2027, label: '2027').net, 10);
    expect(state.summaryFor(year: 2027, month: 1, label: '01').inflow, 10);
    expect(state.currentBalance, -46);
  });

  testWidgets('B1 360px large-text Dec/Jan reverse scroll keeps paired summary',
      (tester) async {
    const account = AccountRecord(
      id: 'ipass', name: 'iPASS Money', type: AccountType.eWallet,
      initialBalance: 0, sortOrder: 0,
    );
    await _pump(tester, account, _FixtureStore(account), 1.3);
    _expectPeriod('2027年', '01月');
    _expectLedgerInkSurface(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
    await tester.pumpAndSettle();
    _expectPeriod('2027年', '01月');
    var crossed = false;
    for (var attempt = 0; attempt < 6; attempt++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -650));
      await tester.pumpAndSettle();
      if (find.text('2026年').evaluate().isNotEmpty) {
        crossed = true;
        break;
      }
    }
    expect(crossed, isTrue, reason: 'December must become first visible');
    _expectPeriod('2026年', '12月');
    for (var attempt = 0; attempt < 8; attempt++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 650));
      await tester.pumpAndSettle();
      if (find.text('2027年').evaluate().isNotEmpty) break;
    }
    _expectPeriod('2027年', '01月');
    expect(tester.takeException(), isNull);
  });

  for (final type in AccountType.values) {
    testWidgets('B1 paired summary for account type ${type.name}', (tester) async {
      final account = AccountRecord(
        id: 'type-${type.name}', name: 'Synthetic ${type.name}',
        type: type, initialBalance: 0, sortOrder: 0,
        currency: type == AccountType.investment
            ? CurrencyCode.usd : CurrencyCode.twd,
      );
      await _pump(tester, account, _FixtureStore(account), 1.3);
      _expectPeriod('2027年', '01月');
      expect(tester.takeException(), isNull);
    });
  }
}

// The first real ledger tile must find an ink-owning Material before the
// swipe GestureDetector; Card's outer Material is too far away for ListTile.
void _expectLedgerInkSurface(WidgetTester tester) {
  final tile = tester.element(find.byType(ExpansionTile).first);
  var materialInsideSwipe = false;
  tile.visitAncestorElements((ancestor) {
    if (ancestor.widget is Material) {
      materialInsideSwipe = true;
      return false;
    }
    if (ancestor.widget is GestureDetector) return false;
    return true;
  });
  expect(materialInsideSwipe, isTrue,
      reason: 'Ledger tile ink surface must be inside the swipe layer');
}

void _expectPeriod(String year, String month) {
  expect(find.text(year), findsOneWidget);
  expect(find.text(month), findsOneWidget);
}

class _FixtureStore implements AccountStore {
  _FixtureStore(this.account);
  final AccountRecord account;

  @override
  Future<List<AccountRecord>> listAccounts({bool includeArchived = false}) async =>
      <AccountRecord>[account];

  @override
  Future<List<AccountEventRecord>> listAccountEvents(String accountName) async =>
      <AccountEventRecord>[
        for (var i = 0; i < 10; i++)
          _event(i, DateTime(2027, 1, 10 - i, 8), 1),
        for (var i = 0; i < 28; i++)
          _event(i + 10, DateTime(2026, 12, 28 - i, 8), -2),
      ];

  AccountEventRecord _event(int index, DateTime date, double amount) =>
      AccountEventRecord(
        id: 'synthetic-$index', accountId: account.id,
        accountName: account.displayName, eventType: 'balance_correction',
        amount: amount, currency: account.currency,
        exchangeRateToBase: account.currency.defaultRateToTwd,
        occurredAt: date, note: 'read-only synthetic ledger',
      );

  @override
  Future<List<TransactionRecord>> listAccountTransactions(String accountName) async =>
      const <TransactionRecord>[];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('B1 fixture forbids account writes');
}

class _NoWriteTransactionStore implements TransactionStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('B1 fixture forbids transaction access');
}

class _ReadOnlyLedgerController extends TransactionLedgerController {
  _ReadOnlyLedgerController()
      : super(
          _NoWriteTransactionStore(),
          installmentRepository: InMemoryCreditCardInstallmentRepository(),
        ) {
    state = const AsyncValue.data(TransactionLedgerState(
      records: <TransactionRecord>[], monthlyIncome: 0, monthlyExpense: 0,
    ));
  }

  @override
  Future<void> load() async {}
}

Future<void> _pump(
  WidgetTester tester, AccountRecord account, _FixtureStore store,
  double textScale,
) async {
  await tester.binding.setSurfaceSize(const Size(360, 800));
  addTearDown(() async => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      accountStoreProvider.overrideWithValue(store),
      transactionLedgerProvider.overrideWith(
        (ref) => _ReadOnlyLedgerController(),
      ),
      accountAvailableBalancePresentationProvider(account).overrideWith(
        (ref) async => null,
      ),
      accountDebitCardSettlementPresentationProvider(account).overrideWith(
        (ref) async => const [],
      ),
      debitCardSettlementReminderReconciliationProvider.overrideWith(
        (ref) async => 0,
      ),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 800)).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: AccountDetailPage(account: account),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}
