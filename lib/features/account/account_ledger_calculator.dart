import '../transaction/transaction_record.dart';
import '../transaction/transaction_type.dart';
import 'account_event_record.dart';
import 'account_record.dart';

class AccountLedgerCalculator {
  const AccountLedgerCalculator();

  double currentBalance({
    required AccountRecord account,
    required Iterable<AccountRecord> accounts,
    required Iterable<AccountEventRecord> events,
    required Iterable<TransactionRecord> transactions,
  }) {
    final accountByName = <String, AccountRecord>{
      for (final item in accounts) item.displayName: item,
    };
    final entries = <_LedgerInput>[
      ...events.map(_LedgerInput.event),
      ...transactions.map(_LedgerInput.transaction),
    ]
      ..sort((left, right) {
        final timeComparison = left.occurredAt.compareTo(right.occurredAt);
        if (timeComparison != 0) return timeComparison;
        if (left.event != null && right.transaction != null) return -1;
        if (left.transaction != null && right.event != null) return 1;
        return left.id.compareTo(right.id);
      });

    var running = account.type == AccountType.loan
        ? -account.currency.roundAmount(account.loanPrincipal)
        : 0.0;

    for (final entry in entries) {
      final event = entry.event;
      if (event != null) {
        if (account.type == AccountType.loan && event.isInitialBalance) {
          continue;
        }
        if (event.isInitialBalance) running = 0;
        running += event.amount;
        continue;
      }

      running += transactionDelta(
        transaction: entry.transaction!,
        account: account,
        accountByName: accountByName,
      );
    }

    return account.currency.roundAmount(running);
  }

  double transactionDelta({
    required TransactionRecord transaction,
    required AccountRecord account,
    required Map<String, AccountRecord> accountByName,
  }) {
    if (transaction.type == TransactionType.transfer) {
      final fromName = transaction.fromAccountName ?? transaction.accountName;
      final toName = transaction.toAccountName ?? '';
      final fromAccount = accountByName[fromName];
      final toAccount = accountByName[toName];
      final fromRate = fromAccount?.currency.defaultRateToTwd ??
          transaction.currency.defaultRateToTwd;
      final toRate = toAccount?.currency.defaultRateToTwd ??
          account.currency.defaultRateToTwd;
      final sourceAmount = transaction.amount;
      final sourceBaseAmount = sourceAmount * fromRate;
      if (fromName == account.displayName) return -sourceAmount;
      if (toName == account.displayName) return sourceBaseAmount / toRate;
      return 0;
    }

    final accountRate = account.currency.defaultRateToTwd;
    final transactionRate = transaction.exchangeRateToBase == 0
        ? transaction.currency.defaultRateToTwd
        : transaction.exchangeRateToBase;
    final amountInAccountCurrency = transaction.currency == account.currency
        ? transaction.amount
        : (transaction.amount * transactionRate) / accountRate;

    if (transaction.type == TransactionType.loan &&
        transaction.category == '還本' &&
        transaction.accountName == account.displayName) {
      return amountInAccountCurrency;
    }
    if (transaction.type == TransactionType.income) {
      return amountInAccountCurrency;
    }
    if (transaction.type == TransactionType.expense) {
      return -amountInAccountCurrency;
    }
    return 0;
  }
}

class _LedgerInput {
  const _LedgerInput._({this.event, this.transaction});

  factory _LedgerInput.event(AccountEventRecord value) {
    return _LedgerInput._(event: value);
  }

  factory _LedgerInput.transaction(TransactionRecord value) {
    return _LedgerInput._(transaction: value);
  }

  final AccountEventRecord? event;
  final TransactionRecord? transaction;

  DateTime get occurredAt => event?.occurredAt ?? transaction!.occurredAt;
  String get id => event?.id ?? transaction!.id;
}
