import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_event_record.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/debit_card_account_profile.dart';
import 'package:my_finance_app/features/account/debit_card_available_balance_read_source.dart';
import 'package:my_finance_app/features/transaction/debit_card_available_balance.dart';
import 'package:my_finance_app/features/transaction/debit_card_available_balance_read_service.dart';
import 'package:my_finance_app/features/transaction/debit_card_settlement.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  const bank = AccountRecord(
    id: 'bank-1',
    name: '薪轉銀行',
    type: AccountType.bank,
    initialBalance: 1000,
    sortOrder: 10,
  );
  const debitOne = AccountRecord(
    id: 'debit-1',
    name: '簽帳卡一',
    type: AccountType.debitCard,
    initialBalance: 0,
    sortOrder: 20,
  );
  const debitTwo = AccountRecord(
    id: 'debit-2',
    name: '簽帳卡二',
    type: AccountType.debitCard,
    initialBalance: 0,
    sortOrder: 30,
  );
  const cash = AccountRecord(
    id: 'cash-1',
    name: '現金',
    type: AccountType.cash,
    initialBalance: 0,
    sortOrder: 40,
  );

  final profile = DebitCardAccountProfile.link(
    debitCardAccountId: debitOne.id,
    linkedBankAccount: bank,
    debitCardCurrency: CurrencyCode.twd,
  );
  final initialEvent = AccountEventRecord(
    id: 'initial-bank-1',
    accountId: bank.id,
    accountName: bank.displayName,
    eventType: 'initial_balance',
    amount: 1000,
    currency: CurrencyCode.twd,
    exchangeRateToBase: 1,
    occurredAt: DateTime.utc(2000),
  );

  TransactionRecord transaction({
    required String id,
    required TransactionType type,
    required double amount,
    String accountName = '薪轉銀行',
    String? fromAccountName,
    String? toAccountName,
  }) {
    return TransactionRecord(
      id: id,
      type: type,
      amount: amount,
      category: type == TransactionType.income ? '薪資' : '日常',
      occurredAt: DateTime.utc(2026, 7, 1, 10),
      accountName: accountName,
      memberName: '自己',
      merchantName: '',
      tagName: '',
      note: '',
      fromAccountName: fromAccountName,
      toAccountName: toAccountName,
    );
  }

  DebitCardPendingSettlement pending({
    required String id,
    required String debitCardAccountId,
    required double amount,
  }) {
    return DebitCardPendingSettlement.authorize(
      id: id,
      debitCardAccountId: debitCardAccountId,
      linkedBankAccountId: bank.id,
      transactionId: 'transaction-$id',
      amount: amount,
      currency: CurrencyCode.twd,
      authorizedAt: DateTime.utc(2026, 7, 1, 12),
    );
  }

  test('loads repository inputs and returns shared-bank available balance', () async {
    final firstPending = pending(
      id: 'pending-1',
      debitCardAccountId: debitOne.id,
      amount: 300,
    );
    final secondPending = pending(
      id: 'pending-2',
      debitCardAccountId: debitTwo.id,
      amount: 200,
    );
    final terminal = pending(
      id: 'confirmed-1',
      debitCardAccountId: debitOne.id,
      amount: 100,
    ).confirm(DateTime.utc(2026, 7, 3, 12));
    final source = _FakeReadSource(
      accounts: const [bank, debitOne, debitTwo, cash],
      profiles: {debitOne.id: profile},
      events: [initialEvent],
      transactions: [
        transaction(
          id: 'income-1',
          type: TransactionType.income,
          amount: 300,
        ),
        transaction(
          id: 'expense-1',
          type: TransactionType.expense,
          amount: 50,
        ),
        transaction(
          id: 'transfer-1',
          type: TransactionType.transfer,
          amount: 100,
          fromAccountName: bank.displayName,
          toAccountName: cash.displayName,
        ),
      ],
      settlements: [firstPending, secondPending, terminal],
    );

    final snapshot = await DebitCardAvailableBalanceReadService(
      source: source,
    ).load(debitOne.id);

    expect(snapshot.ledgerBalance, 1150);
    expect(snapshot.reservedPendingAmount, 500);
    expect(snapshot.availableBalance, 650);
    expect(snapshot.activeReservationCount, 2);
    expect(snapshot.canAuthorize(650), isTrue);
    expect(snapshot.canAuthorize(651), isFalse);
    expect(source.requestedEventAccountNames, [bank.displayName]);
    expect(source.requestedTransactionAccountNames, [bank.displayName]);
    expect(source.pendingSettlementReadCount, 1);
  });

  test('missing debit-card account fails closed', () async {
    final source = _FakeReadSource(
      accounts: const [bank],
      profiles: const {},
      events: const [],
      transactions: const [],
      settlements: const [],
    );

    await expectLater(
      DebitCardAvailableBalanceReadService(source: source).load('missing'),
      throwsA(
        isA<DebitCardAvailableBalanceReadException>().having(
          (error) => error.code,
          'code',
          DebitCardAvailableBalanceReadErrorCode.debitCardAccountNotFound,
        ),
      ),
    );
  });

  test('missing profile fails closed', () async {
    final source = _FakeReadSource(
      accounts: const [bank, debitOne],
      profiles: const {},
      events: const [],
      transactions: const [],
      settlements: const [],
    );

    await expectLater(
      DebitCardAvailableBalanceReadService(source: source).load(debitOne.id),
      throwsA(
        isA<DebitCardAvailableBalanceReadException>().having(
          (error) => error.code,
          'code',
          DebitCardAvailableBalanceReadErrorCode.profileNotFound,
        ),
      ),
    );
  });

  test('missing linked bank account fails closed', () async {
    final source = _FakeReadSource(
      accounts: const [debitOne],
      profiles: {debitOne.id: profile},
      events: const [],
      transactions: const [],
      settlements: const [],
    );

    await expectLater(
      DebitCardAvailableBalanceReadService(source: source).load(debitOne.id),
      throwsA(
        isA<DebitCardAvailableBalanceReadException>().having(
          (error) => error.code,
          'code',
          DebitCardAvailableBalanceReadErrorCode.linkedBankAccountNotFound,
        ),
      ),
    );
  });

  test('archived linked bank validation remains fail closed', () async {
    final source = _FakeReadSource(
      accounts: [bank.copyWith(isArchived: true), debitOne],
      profiles: {debitOne.id: profile},
      events: [initialEvent],
      transactions: const [],
      settlements: const [],
    );

    await expectLater(
      DebitCardAvailableBalanceReadService(source: source).load(debitOne.id),
      throwsA(
        isA<DebitCardAvailableBalanceContextException>().having(
          (error) => error.code,
          'code',
          DebitCardAvailableBalanceContextErrorCode.linkedBankAccountArchived,
        ),
      ),
    );
  });
}

class _FakeReadSource implements DebitCardAvailableBalanceReadSource {
  _FakeReadSource({
    required this.accounts,
    required this.profiles,
    required this.events,
    required this.transactions,
    required this.settlements,
  });

  final List<AccountRecord> accounts;
  final Map<String, DebitCardAccountProfile> profiles;
  final List<AccountEventRecord> events;
  final List<TransactionRecord> transactions;
  final List<DebitCardPendingSettlement> settlements;

  final List<String> requestedEventAccountNames = [];
  final List<String> requestedTransactionAccountNames = [];
  int pendingSettlementReadCount = 0;

  @override
  Future<DebitCardAccountProfile?> getDebitCardProfile(String accountId) async {
    return profiles[accountId];
  }

  @override
  Future<List<AccountRecord>> listAccounts({
    bool includeArchived = false,
  }) async {
    if (includeArchived) return List.of(accounts);
    return accounts.where((account) => !account.isArchived).toList();
  }

  @override
  Future<List<AccountEventRecord>> listAccountEvents(
    String accountName,
  ) async {
    requestedEventAccountNames.add(accountName);
    return events.where((event) => event.accountName == accountName).toList();
  }

  @override
  Future<List<TransactionRecord>> listAccountTransactions(
    String accountName,
  ) async {
    requestedTransactionAccountNames.add(accountName);
    return transactions.where((transaction) {
      return transaction.accountName == accountName ||
          transaction.fromAccountName == accountName ||
          transaction.toAccountName == accountName;
    }).toList();
  }

  @override
  Future<List<DebitCardPendingSettlement>>
      listPendingDebitCardSettlements() async {
    pendingSettlementReadCount += 1;
    return List.of(settlements);
  }
}
