import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_event_record.dart';
import 'package:my_finance_app/features/account/account_providers.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/account_store.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_providers.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_repository.dart';
import 'package:my_finance_app/features/plan/plan_payment_entry_flow.dart';
import 'package:my_finance_app/features/transaction/transaction_providers.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_store.dart';

void main() {
  testWidgets('Home repayment entry loads account data before first sheet render', (tester) async {
    final accountStore = _DelayedAccountStore(const [
      AccountRecord(
        id: 'card-1',
        name: '信用卡',
        suffix: '8888',
        type: AccountType.creditCard,
        initialBalance: 0,
        sortOrder: 10,
        creditLimit: 50000,
        statementDay: 10,
        paymentDueDay: 25,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountStoreProvider.overrideWithValue(accountStore),
          transactionStoreProvider.overrideWithValue(_DelayedTransactionStore()),
          creditCardInstallmentRepositoryProvider.overrideWithValue(InMemoryCreditCardInstallmentRepository()),
        ],
        child: const MaterialApp(home: _RepaymentEntryHarness()),
      ),
    );

    await tester.tap(find.text('開啟還款'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('選擇繳款 / 還款類型'), findsOneWidget);
    expect(find.text('信用卡繳款'), findsOneWidget);
    expect(find.textContaining('1 張'), findsOneWidget);
    expect(find.textContaining('尚未建立信用卡帳戶'), findsNothing);
  });
}

class _RepaymentEntryHarness extends ConsumerWidget {
  const _RepaymentEntryHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () async => openPlanPaymentEntryFlow(context, ref),
          child: const Text('開啟還款'),
        ),
      ),
    );
  }
}

class _DelayedAccountStore extends AccountStore {
  _DelayedAccountStore(this.accounts);

  final List<AccountRecord> accounts;

  @override
  Future<List<AccountRecord>> listAccounts({bool includeArchived = false}) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
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

class _DelayedTransactionStore implements TransactionStore {
  @override
  Future<void> insert(TransactionRecord record) async {}

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
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return const [];
  }

  @override
  Future<double> monthlyIncome(DateTime month) async => 0;

  @override
  Future<double> monthlyExpense(DateTime month) async => 0;
}
