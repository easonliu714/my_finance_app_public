import '../account/account_ledger_calculator.dart';
import '../account/account_record.dart';
import '../account/debit_card_available_balance_read_source.dart';
import 'debit_card_available_balance.dart';

enum DebitCardAvailableBalanceReadErrorCode {
  debitCardAccountNotFound,
  profileNotFound,
  linkedBankAccountNotFound,
}

class DebitCardAvailableBalanceReadException implements Exception {
  const DebitCardAvailableBalanceReadException(this.code, this.message);

  final DebitCardAvailableBalanceReadErrorCode code;
  final String message;

  @override
  String toString() =>
      'DebitCardAvailableBalanceReadException($code): $message';
}

class DebitCardAvailableBalanceReadService {
  const DebitCardAvailableBalanceReadService({
    required this.source,
    this.ledgerCalculator = const AccountLedgerCalculator(),
    this.snapshotService = const DebitCardAvailableBalanceService(),
  });

  final DebitCardAvailableBalanceReadSource source;
  final AccountLedgerCalculator ledgerCalculator;
  final DebitCardAvailableBalanceService snapshotService;

  Future<DebitCardAvailableBalanceSnapshot> load(
    String debitCardAccountId,
  ) async {
    final normalizedId = debitCardAccountId.trim();
    final accounts = await source.listAccounts(includeArchived: true);
    final debitCardAccount = _findAccount(accounts, normalizedId);
    if (debitCardAccount == null) {
      throw DebitCardAvailableBalanceReadException(
        DebitCardAvailableBalanceReadErrorCode.debitCardAccountNotFound,
        'Debit-card account $normalizedId does not exist.',
      );
    }

    final profile = await source.getDebitCardProfile(normalizedId);
    if (profile == null) {
      throw DebitCardAvailableBalanceReadException(
        DebitCardAvailableBalanceReadErrorCode.profileNotFound,
        'Debit-card profile $normalizedId does not exist.',
      );
    }

    final linkedBankAccount = _findAccount(
      accounts,
      profile.linkedBankAccountId,
    );
    if (linkedBankAccount == null) {
      throw DebitCardAvailableBalanceReadException(
        DebitCardAvailableBalanceReadErrorCode.linkedBankAccountNotFound,
        'Linked bank account ${profile.linkedBankAccountId} does not exist.',
      );
    }

    final events = await source.listAccountEvents(
      linkedBankAccount.displayName,
    );
    final transactions = await source.listAccountTransactions(
      linkedBankAccount.displayName,
    );
    final settlements = await source.listPendingDebitCardSettlements();
    final ledgerBalance = ledgerCalculator.currentBalance(
      account: linkedBankAccount,
      accounts: accounts,
      events: events,
      transactions: transactions,
    );

    return snapshotService.buildSnapshot(
      profile: profile,
      debitCardAccount: debitCardAccount,
      linkedBankAccount: linkedBankAccount,
      currentBankLedgerBalance: ledgerBalance,
      settlements: settlements,
    );
  }

  AccountRecord? _findAccount(
    Iterable<AccountRecord> accounts,
    String id,
  ) {
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }
}
