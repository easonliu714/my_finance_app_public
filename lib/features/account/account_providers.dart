import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../transaction/transaction_record.dart';
import '../transaction/transaction_type.dart';
import 'account_event_record.dart';
import 'account_record.dart';
import 'account_repository.dart';
import 'account_store.dart';
import 'debit_card_account_store.dart';

final accountStoreProvider = Provider<AccountStore>((ref) {
  return AccountRepository.instance;
});

final debitCardAccountStoreProvider = Provider<DebitCardAccountStore>((ref) {
  return AccountRepository.instance;
});

final accountListProvider = StateNotifierProvider<AccountListController, AsyncValue<List<AccountRecord>>>((ref) {
  final store = ref.watch(accountStoreProvider);
  final controller = AccountListController(store);
  controller.load();
  return controller;
});

final accountDetailProvider = StateNotifierProvider.autoDispose.family<AccountDetailController, AsyncValue<AccountDetailState>, AccountRecord>((ref, account) {
  final store = ref.watch(accountStoreProvider);
  final controller = AccountDetailController(store, account);
  controller.load();
  return controller;
});

class AccountListController extends StateNotifier<AsyncValue<List<AccountRecord>>> {
  AccountListController(this._store) : super(const AsyncValue.loading());

  final AccountStore _store;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _store.listAccounts());
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> addAccount({
    required String name,
    required AccountType type,
    required double initialBalance,
    String suffix = '',
    CurrencyCode currency = CurrencyCode.twd,
    double creditLimit = 0,
    int statementDay = 1,
    int paymentDueDay = 1,
    bool paymentReminderEnabled = false,
    int reminderDaysBefore = 3,
    double loanPrincipal = 0,
    double annualInterestRate = 0,
    int loanTermMonths = 0,
    LoanRepaymentMethod loanRepaymentMethod = LoanRepaymentMethod.equalPrincipalAndInterest,
    int loanPaymentDueDay = 1,
    bool loanReminderEnabled = false,
    int loanReminderDaysBefore = 3,
    String note = '',
  }) async {
    final current = state.valueOrNull ?? await _store.listAccounts(includeArchived: true);
    final item = AccountRecord(
      id: const Uuid().v4(),
      name: name.trim(),
      type: type,
      initialBalance: initialBalance,
      sortOrder: current.length * 10 + 100,
      suffix: suffix.trim(),
      currency: currency,
      creditLimit: creditLimit,
      statementDay: statementDay,
      paymentDueDay: paymentDueDay,
      paymentReminderEnabled: paymentReminderEnabled,
      reminderDaysBefore: reminderDaysBefore,
      loanPrincipal: loanPrincipal,
      annualInterestRate: annualInterestRate,
      loanTermMonths: loanTermMonths,
      loanRepaymentMethod: loanRepaymentMethod,
      loanPaymentDueDay: loanPaymentDueDay,
      loanReminderEnabled: loanReminderEnabled,
      loanReminderDaysBefore: loanReminderDaysBefore,
      note: note.trim(),
    );
    _assertUniqueAccountKey(current, item);
    await _store.upsertAccount(item);
    await load();
  }

  Future<void> updateAccount(AccountRecord item) async {
    final current = state.valueOrNull ?? await _store.listAccounts(includeArchived: true);
    _assertUniqueAccountKey(current, item);
    await _store.upsertAccount(item);
    await load();
  }


  Future<void> archive(String id) async {
    await _store.archiveAccount(id);
    await load();
  }

  void _assertUniqueAccountKey(List<AccountRecord> current, AccountRecord item) {
    final duplicated = current.any(
      (account) => account.id != item.id && account.name.trim() == item.name.trim() && account.suffix.trim() == item.suffix.trim(),
    );
    if (duplicated) {
      final suffixText = item.suffix.trim().isEmpty ? '空白尾碼' : item.suffix.trim();
      throw StateError('帳戶名稱與尾碼已存在：${item.name.trim()}・$suffixText');
    }
  }
}

class AccountFlowSummary {
  const AccountFlowSummary({required this.label, required this.inflow, required this.outflow});
  final String label;
  final double inflow;
  final double outflow;
  double get net => inflow - outflow;
}

class AccountDetailState {
  const AccountDetailState({required this.account, required this.items});
  final AccountRecord account;
  final List<AccountLedgerItem> items;

  double get currentBalance => items.isEmpty ? 0 : items.last.runningBalance;
  double get outstandingLoanPrincipal => account.type == AccountType.loan ? currentBalance.abs() : 0;

  AccountFlowSummary get yearSummary {
    final now = DateTime.now();
    return summaryFor(year: now.year, label: '${now.year} 年帳戶流量');
  }

  AccountFlowSummary get monthSummary {
    final now = DateTime.now();
    return summaryFor(year: now.year, month: now.month, label: '${now.year}/${now.month.toString().padLeft(2, '0')} 帳戶流量');
  }

  AccountFlowSummary summaryFor({required int year, int? month, required String label}) {
    var inflow = 0.0;
    var outflow = 0.0;
    for (final item in items) {
      if (item.isInitialBalance) continue;
      if (item.occurredAt.year != year) continue;
      if (month != null && item.occurredAt.month != month) continue;
      if (item.amountForAccount >= 0) {
        inflow += item.amountForAccount;
      } else {
        outflow += item.amountForAccount.abs();
      }
    }
    return AccountFlowSummary(label: label, inflow: inflow, outflow: outflow);
  }
}

class AccountLedgerItem {
  const AccountLedgerItem({required this.id, required this.title, required this.subtitle, required this.occurredAt, required this.amountForAccount, required this.runningBalance, this.transaction, this.event});
  final String id;
  final String title;
  final String subtitle;
  final DateTime occurredAt;
  final double amountForAccount;
  final double runningBalance;
  final TransactionRecord? transaction;
  final AccountEventRecord? event;
  bool get isSensitiveEvent => event?.isInitialBalance == true || event?.isBalanceCorrection == true;
  bool get isInitialBalance => event?.isInitialBalance == true;
  bool get isLoanPrincipalRepayment => transaction?.type == TransactionType.loan && transaction?.category == '還本';
  bool get isLoanRepaymentCandidate {
    final tx = transaction;
    if (tx == null) return false;
    final hasPeriod = RegExp(r'第\s*\d+\s*期').hasMatch(tx.note);
    if (!hasPeriod && tx.tagName != '還款') return false;
    final isPrincipal = tx.type == TransactionType.loan && tx.category == '還本';
    final isInterest = tx.type == TransactionType.expense && tx.category == '利息支出';
    return tx.tagName == '還款' && hasPeriod && (isPrincipal || isInterest);
  }
}

class AccountDetailController extends StateNotifier<AsyncValue<AccountDetailState>> {
  AccountDetailController(this._store, this._account) : super(const AsyncValue.loading());
  final AccountStore _store;
  final AccountRecord _account;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final accounts = await _store.listAccounts(includeArchived: true);
      final accountByName = {for (final account in accounts) account.displayName: account};
      final events = await _store.listAccountEvents(_account.displayName);
      final transactions = await _store.listAccountTransactions(_account.displayName);
      final raw = <_RawLedgerItem>[
        ...events.map((event) => _RawLedgerItem(event: event)),
        ...transactions.map((transaction) => _RawLedgerItem(transaction: transaction)),
      ]..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      var running = _account.type == AccountType.loan ? -_account.currency.roundAmount(_account.loanPrincipal) : 0.0;
      final items = <AccountLedgerItem>[];
      if (_account.type == AccountType.loan && _account.loanPrincipal > 0) {
        items.add(AccountLedgerItem(
          id: '${_account.id}-loan-principal',
          title: '貸款本金設定',
          subtitle: '原始本金 ${_formatNumber(_account.loanPrincipal)} ${_account.currency.code}',
          occurredAt: DateTime(1970),
          amountForAccount: -_account.currency.roundAmount(_account.loanPrincipal),
          runningBalance: running,
        ));
      }
      for (final rawItem in raw) {
        final event = rawItem.event;
        final tx = rawItem.transaction;
        double delta;
        String title;
        String subtitle;
        if (event != null) {
          if (_account.type == AccountType.loan && event.isInitialBalance) {
            continue;
          }
          delta = event.amount;
          title = event.isInitialBalance ? '初始值設定' : '餘額校正';
          subtitle = event.note;
          if (event.isInitialBalance) running = 0;
        } else {
          delta = _transactionDelta(tx!, accountByName);
          title = tx.category;
          subtitle = _transactionSubtitle(tx);
        }
        running += delta;
        items.add(AccountLedgerItem(id: event?.id ?? tx!.id, title: title, subtitle: subtitle, occurredAt: rawItem.occurredAt, amountForAccount: delta, runningBalance: running, event: event, transaction: tx));
      }
      state = AsyncValue.data(AccountDetailState(account: _account, items: items));
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  String _transactionSubtitle(TransactionRecord tx) {
    if (tx.type == TransactionType.transfer) {
      return '${tx.fromAccountName ?? tx.accountName} → ${tx.toAccountName ?? ''}${tx.note.isEmpty ? '' : '・${tx.note}'}';
    }
    if (tx.isLoanRepayment) {
      return '${tx.accountName}・還款群組 ${tx.repaymentGroupId}${tx.note.isEmpty ? '' : '・${tx.note}'}';
    }
    return '${tx.accountName}${tx.note.isEmpty ? '' : '・${tx.note}'}';
  }

  double _transactionDelta(TransactionRecord tx, Map<String, AccountRecord> accountByName) {
    if (tx.type == TransactionType.transfer) {
      final fromName = tx.fromAccountName ?? tx.accountName;
      final toName = tx.toAccountName ?? '';
      final fromAccount = accountByName[fromName];
      final toAccount = accountByName[toName];
      final fromRate = fromAccount?.currency.defaultRateToTwd ?? tx.currency.defaultRateToTwd;
      final toRate = toAccount?.currency.defaultRateToTwd ?? _account.currency.defaultRateToTwd;
      final sourceAmount = tx.amount;
      final sourceBaseAmount = sourceAmount * fromRate;
      if (fromName == _account.displayName) return -sourceAmount;
      if (toName == _account.displayName) return sourceBaseAmount / toRate;
      return 0;
    }
    final accountRate = _account.currency.defaultRateToTwd;
    final transactionRate = tx.exchangeRateToBase == 0 ? tx.currency.defaultRateToTwd : tx.exchangeRateToBase;
    final amountInAccountCurrency = tx.currency == _account.currency ? tx.amount : (tx.amount * transactionRate) / accountRate;
    if (tx.type == TransactionType.loan && tx.category == '還本' && tx.accountName == _account.displayName) return amountInAccountCurrency;
    if (tx.type == TransactionType.income) return amountInAccountCurrency;
    if (tx.type == TransactionType.expense) return -amountInAccountCurrency;
    return 0;
  }

  Future<AccountEventRecord> addBalanceCorrection(double correctedBalance, {String note = ''}) async {
    final current = state.valueOrNull?.currentBalance ?? 0;
    final diff = correctedBalance - current;
    final event = AccountEventRecord(id: const Uuid().v4(), accountId: _account.id, accountName: _account.displayName, eventType: 'balance_correction', amount: diff, currency: _account.currency, exchangeRateToBase: _account.currency.defaultRateToTwd, occurredAt: DateTime.now(), note: note.isEmpty ? '餘額校正：${_formatNumber(current)} → ${_formatNumber(correctedBalance)}' : note);
    await _store.upsertAccountEvent(event);
    await load();
    return event;
  }

  Future<void> deleteEvent(String id) async {
    await _store.deleteAccountEvent(id);
    await load();
  }
}

class _RawLedgerItem {
  const _RawLedgerItem({this.event, this.transaction});
  final AccountEventRecord? event;
  final TransactionRecord? transaction;
  DateTime get occurredAt => event?.occurredAt ?? transaction!.occurredAt;
}

String _formatNumber(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
