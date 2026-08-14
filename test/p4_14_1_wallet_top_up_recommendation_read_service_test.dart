import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_event_record.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/wallet_top_up_recommendation.dart';
import 'package:my_finance_app/features/account/wallet_top_up_recommendation_read_service.dart';
import 'package:my_finance_app/features/account/wallet_top_up_recommendation_read_source.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  const wallet = AccountRecord(
    id: 'wallet-1',
    name: '日常錢包',
    type: AccountType.eWallet,
    initialBalance: 80,
    sortOrder: 10,
  );
  const bank = AccountRecord(
    id: 'bank-1',
    name: '薪轉銀行',
    type: AccountType.bank,
    initialBalance: 1000,
    sortOrder: 20,
  );
  const cash = AccountRecord(
    id: 'cash-1',
    name: '現金',
    type: AccountType.cash,
    initialBalance: 0,
    sortOrder: 30,
  );
  final evaluatedAt = DateTime.utc(2026, 7, 4, 6);

  WalletTopUpProfile profile({
    String targetAccountId = 'wallet-1',
    String fundingAccountId = 'bank-1',
    CurrencyCode currency = CurrencyCode.twd,
    double threshold = 150,
    double targetBalance = 500,
  }) {
    return WalletTopUpProfile(
      targetAccountId: targetAccountId,
      fundingAccountId: fundingAccountId,
      currency: currency,
      threshold: threshold,
      amountMode: WalletTopUpAmountMode.targetBalance,
      targetBalance: targetBalance,
    );
  }

  AccountEventRecord initialEvent(AccountRecord account, double amount) {
    return AccountEventRecord(
      id: 'initial-${account.id}',
      accountId: account.id,
      accountName: account.displayName,
      eventType: 'initial_balance',
      amount: amount,
      currency: account.currency,
      exchangeRateToBase: account.currency.defaultRateToTwd,
      occurredAt: DateTime.utc(2000),
    );
  }

  TransactionRecord transaction({
    required String id,
    required TransactionType type,
    required double amount,
    required String accountName,
    String? fromAccountName,
    String? toAccountName,
    CurrencyCode currency = CurrencyCode.twd,
  }) {
    return TransactionRecord(
      id: id,
      type: type,
      amount: amount,
      category: type == TransactionType.income ? '收入' : '日常',
      occurredAt: DateTime.utc(2026, 7, 1, 10),
      accountName: accountName,
      memberName: '自己',
      merchantName: '',
      tagName: '',
      note: '',
      currency: currency,
      exchangeRateToBase: currency.defaultRateToTwd,
      fromAccountName: fromAccountName,
      toAccountName: toAccountName,
    );
  }

  _FakeWalletTopUpReadSource standardSource({
    double walletInitialBalance = 80,
    double bankInitialBalance = 1000,
  }) {
    return _FakeWalletTopUpReadSource(
      accounts: const [wallet, bank, cash],
      events: [
        initialEvent(wallet, walletInitialBalance),
        initialEvent(bank, bankInitialBalance),
      ],
      transactions: [
        transaction(
          id: 'wallet-income',
          type: TransactionType.income,
          amount: 20,
          accountName: wallet.displayName,
        ),
        transaction(
          id: 'wallet-expense',
          type: TransactionType.expense,
          amount: 10,
          accountName: wallet.displayName,
        ),
        transaction(
          id: 'bank-income',
          type: TransactionType.income,
          amount: 200,
          accountName: bank.displayName,
        ),
        transaction(
          id: 'bank-expense',
          type: TransactionType.expense,
          amount: 100,
          accountName: bank.displayName,
        ),
        transaction(
          id: 'bank-to-wallet',
          type: TransactionType.transfer,
          amount: 40,
          accountName: bank.displayName,
          fromAccountName: bank.displayName,
          toAccountName: wallet.displayName,
        ),
      ],
    );
  }

  test('loads both ledgers and returns repository-backed suggestion', () async {
    final source = standardSource();
    final result = await WalletTopUpRecommendationReadService(
      source: source,
    ).evaluate(profile: profile(), evaluatedAt: evaluatedAt);

    expect(result, isA<WalletTopUpSuggestion>());
    final suggestion = result as WalletTopUpSuggestion;
    expect(suggestion.currentAvailableBalance, 130);
    expect(suggestion.fundingAvailableBalance, 1060);
    expect(suggestion.suggestedAmount, 370);
    expect(suggestion.fundingSufficient, isTrue);
    expect(source.includeArchivedRequests, [true]);
    expect(
      source.requestedEventAccountNames,
      [wallet.displayName, bank.displayName],
    );
    expect(
      source.requestedTransactionAccountNames,
      [wallet.displayName, bank.displayName],
    );
  });

  test('balance at threshold returns no suggestion', () async {
    final source = _FakeWalletTopUpReadSource(
      accounts: const [wallet, bank],
      events: [initialEvent(wallet, 150), initialEvent(bank, 1000)],
      transactions: const [],
    );

    final result = await WalletTopUpRecommendationReadService(
      source: source,
    ).evaluate(profile: profile(), evaluatedAt: evaluatedAt);

    expect(result, isA<WalletTopUpNoSuggestion>());
    expect(
      (result as WalletTopUpNoSuggestion).reason,
      WalletTopUpNoSuggestionReason.balanceAtOrAboveThreshold,
    );
  });

  test('funding insufficiency is returned as review information', () async {
    final result = await WalletTopUpRecommendationReadService(
      source: standardSource(bankInitialBalance: 100),
    ).evaluate(
      profile: profile(),
      evaluatedAt: evaluatedAt,
    ) as WalletTopUpSuggestion;

    expect(result.currentAvailableBalance, 130);
    expect(result.fundingAvailableBalance, 160);
    expect(result.suggestedAmount, 370);
    expect(result.fundingSufficient, isFalse);
    expect(result.fundingShortfall, 210);
  });

  test('missing target account fails before ledger reads', () async {
    final source = _FakeWalletTopUpReadSource(
      accounts: const [bank],
      events: const [],
      transactions: const [],
    );

    await expectLater(
      WalletTopUpRecommendationReadService(source: source).evaluate(
        profile: profile(),
        evaluatedAt: evaluatedAt,
      ),
      throwsA(
        isA<WalletTopUpRecommendationReadException>().having(
          (error) => error.code,
          'code',
          WalletTopUpRecommendationReadErrorCode.targetAccountNotFound,
        ),
      ),
    );
    expect(source.requestedEventAccountNames, isEmpty);
    expect(source.requestedTransactionAccountNames, isEmpty);
  });

  test('missing funding account fails before ledger reads', () async {
    final source = _FakeWalletTopUpReadSource(
      accounts: const [wallet],
      events: const [],
      transactions: const [],
    );

    await expectLater(
      WalletTopUpRecommendationReadService(source: source).evaluate(
        profile: profile(),
        evaluatedAt: evaluatedAt,
      ),
      throwsA(
        isA<WalletTopUpRecommendationReadException>().having(
          (error) => error.code,
          'code',
          WalletTopUpRecommendationReadErrorCode.fundingAccountNotFound,
        ),
      ),
    );
    expect(source.requestedEventAccountNames, isEmpty);
    expect(source.requestedTransactionAccountNames, isEmpty);
  });

  test('archived target remains fail closed through pure validation', () async {
    final archivedWallet = wallet.copyWith(isArchived: true);
    final source = _FakeWalletTopUpReadSource(
      accounts: [archivedWallet, bank],
      events: [initialEvent(archivedWallet, 80), initialEvent(bank, 1000)],
      transactions: const [],
    );

    await expectLater(
      WalletTopUpRecommendationReadService(source: source).evaluate(
        profile: profile(),
        evaluatedAt: evaluatedAt,
      ),
      throwsA(
        isA<WalletTopUpRecommendationException>().having(
          (error) => error.code,
          'code',
          WalletTopUpRecommendationErrorCode.targetAccountArchived,
        ),
      ),
    );
  });

  test('archived funding remains fail closed through pure validation', () async {
    final archivedBank = bank.copyWith(isArchived: true);
    final source = _FakeWalletTopUpReadSource(
      accounts: [wallet, archivedBank],
      events: [initialEvent(wallet, 80), initialEvent(archivedBank, 1000)],
      transactions: const [],
    );

    await expectLater(
      WalletTopUpRecommendationReadService(source: source).evaluate(
        profile: profile(),
        evaluatedAt: evaluatedAt,
      ),
      throwsA(
        isA<WalletTopUpRecommendationException>().having(
          (error) => error.code,
          'code',
          WalletTopUpRecommendationErrorCode.fundingAccountArchived,
        ),
      ),
    );
  });

  test('currency mismatch remains fail closed through pure validation', () async {
    final usdBank = bank.copyWith(currency: CurrencyCode.usd);
    final source = _FakeWalletTopUpReadSource(
      accounts: [wallet, usdBank],
      events: [initialEvent(wallet, 80), initialEvent(usdBank, 1000)],
      transactions: const [],
    );

    await expectLater(
      WalletTopUpRecommendationReadService(source: source).evaluate(
        profile: profile(),
        evaluatedAt: evaluatedAt,
      ),
      throwsA(
        isA<WalletTopUpRecommendationException>().having(
          (error) => error.code,
          'code',
          WalletTopUpRecommendationErrorCode.currencyMismatch,
        ),
      ),
    );
  });

  test('same account reads one ledger and then fails closed', () async {
    final source = _FakeWalletTopUpReadSource(
      accounts: const [wallet],
      events: [initialEvent(wallet, 80)],
      transactions: const [],
    );

    await expectLater(
      WalletTopUpRecommendationReadService(source: source).evaluate(
        profile: profile(fundingAccountId: 'wallet-1'),
        evaluatedAt: evaluatedAt,
      ),
      throwsA(
        isA<WalletTopUpRecommendationException>().having(
          (error) => error.code,
          'code',
          WalletTopUpRecommendationErrorCode.fundingAccountMustDiffer,
        ),
      ),
    );
    expect(source.requestedEventAccountNames, [wallet.displayName]);
    expect(source.requestedTransactionAccountNames, [wallet.displayName]);
  });
}

class _FakeWalletTopUpReadSource
    implements WalletTopUpRecommendationReadSource {
  _FakeWalletTopUpReadSource({
    required this.accounts,
    required this.events,
    required this.transactions,
  });

  final List<AccountRecord> accounts;
  final List<AccountEventRecord> events;
  final List<TransactionRecord> transactions;
  final List<bool> includeArchivedRequests = [];
  final List<String> requestedEventAccountNames = [];
  final List<String> requestedTransactionAccountNames = [];

  @override
  Future<List<AccountRecord>> listAccounts({
    bool includeArchived = false,
  }) async {
    includeArchivedRequests.add(includeArchived);
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
}
