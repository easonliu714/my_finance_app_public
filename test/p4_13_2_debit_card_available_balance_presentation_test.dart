import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_event_record.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/debit_card_account_profile.dart';
import 'package:my_finance_app/features/account/debit_card_available_balance_presentation.dart';
import 'package:my_finance_app/features/account/debit_card_available_balance_read_source.dart';
import 'package:my_finance_app/features/transaction/debit_card_available_balance_read_service.dart';
import 'package:my_finance_app/features/transaction/debit_card_settlement.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';

void main() {
  const bank = AccountRecord(
    id: 'bank-1',
    name: '薪轉銀行',
    type: AccountType.bank,
    initialBalance: 1000,
    sortOrder: 10,
  );
  const debitA = AccountRecord(
    id: 'debit-a',
    name: 'A 簽帳卡',
    type: AccountType.debitCard,
    initialBalance: 0,
    sortOrder: 20,
  );
  const debitB = AccountRecord(
    id: 'debit-b',
    name: 'B 簽帳卡',
    type: AccountType.debitCard,
    initialBalance: 0,
    sortOrder: 30,
  );
  const unlinkedBank = AccountRecord(
    id: 'bank-2',
    name: '備用銀行',
    type: AccountType.bank,
    initialBalance: 300,
    sortOrder: 40,
  );
  const cash = AccountRecord(
    id: 'cash-1',
    name: '現金',
    type: AccountType.cash,
    initialBalance: 100,
    sortOrder: 50,
  );

  final profileA = DebitCardAccountProfile.link(
    debitCardAccountId: debitA.id,
    linkedBankAccount: bank,
    debitCardCurrency: CurrencyCode.twd,
  );
  final profileB = DebitCardAccountProfile.link(
    debitCardAccountId: debitB.id,
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

  DebitCardAvailableBalancePresentationService createService(
    _FakeReadSource source,
  ) {
    return DebitCardAvailableBalancePresentationService(
      source: source,
      readService: DebitCardAvailableBalanceReadService(source: source),
    );
  }

  test('debit-card context exposes linked-bank shared pool', () async {
    final source = _FakeReadSource(
      accounts: const [bank, debitA, debitB, unlinkedBank, cash],
      profiles: {debitA.id: profileA, debitB.id: profileB},
      events: [initialEvent],
      transactions: const [],
      settlements: [
        pending(id: 'pending-a', debitCardAccountId: debitA.id, amount: 300),
        pending(id: 'pending-b', debitCardAccountId: debitB.id, amount: 200),
      ],
    );

    final presentation = await createService(source).load(debitA);

    expect(presentation, isNotNull);
    expect(presentation!.isDebitCardContext, isTrue);
    expect(presentation.linkedBankAccount.id, bank.id);
    expect(presentation.linkedDebitCardAccounts, [debitA]);
    expect(presentation.snapshot.ledgerBalance, 1000);
    expect(presentation.snapshot.reservedPendingAmount, 500);
    expect(presentation.snapshot.availableBalance, 500);
    expect(presentation.relationshipLabel, contains(bank.displayName));
  });

  test('linked-bank context lists cards and uses one shared pool', () async {
    final terminal = pending(
      id: 'terminal',
      debitCardAccountId: debitA.id,
      amount: 100,
    ).confirm(DateTime.utc(2026, 7, 3, 12));
    final source = _FakeReadSource(
      accounts: const [bank, debitB, debitA, unlinkedBank, cash],
      profiles: {debitA.id: profileA, debitB.id: profileB},
      events: [initialEvent],
      transactions: const [],
      settlements: [
        pending(id: 'pending-a', debitCardAccountId: debitA.id, amount: 700),
        pending(id: 'pending-b', debitCardAccountId: debitB.id, amount: 500),
        terminal,
      ],
    );

    final presentation = await createService(source).load(bank);

    expect(presentation, isNotNull);
    expect(presentation!.isLinkedBankContext, isTrue);
    expect(
      presentation.linkedDebitCardAccounts.map((item) => item.id),
      [debitA.id, debitB.id],
    );
    expect(presentation.snapshot.reservedPendingAmount, 1200);
    expect(presentation.snapshot.availableBalance, -200);
    expect(presentation.snapshot.isOverReserved, isTrue);
    expect(presentation.relationshipLabel, contains(debitA.displayName));
    expect(presentation.relationshipLabel, contains(debitB.displayName));
  });

  test('unlinked bank and unrelated account return no presentation', () async {
    final source = _FakeReadSource(
      accounts: const [bank, debitA, unlinkedBank, cash],
      profiles: {debitA.id: profileA},
      events: [initialEvent],
      transactions: const [],
      settlements: const [],
    );

    expect(await createService(source).load(unlinkedBank), isNull);
    expect(await createService(source).load(cash), isNull);
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

  @override
  Future<DebitCardAccountProfile?> getDebitCardProfile(String accountId) async {
    return profiles[accountId];
  }

  @override
  Future<List<AccountRecord>> listAccounts({
    bool includeArchived = false,
  }) async {
    if (includeArchived) return List<AccountRecord>.of(accounts);
    return accounts.where((account) => !account.isArchived).toList();
  }

  @override
  Future<List<AccountEventRecord>> listAccountEvents(
    String accountName,
  ) async {
    return events.where((event) => event.accountName == accountName).toList();
  }

  @override
  Future<List<TransactionRecord>> listAccountTransactions(
    String accountName,
  ) async {
    return transactions.where((transaction) {
      return transaction.accountName == accountName ||
          transaction.fromAccountName == accountName ||
          transaction.toAccountName == accountName;
    }).toList();
  }

  @override
  Future<List<DebitCardPendingSettlement>>
      listPendingDebitCardSettlements() async {
    return List<DebitCardPendingSettlement>.of(settlements);
  }
}
