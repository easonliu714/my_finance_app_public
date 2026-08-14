import 'dart:math' as math;

import '../account/account_record.dart';
import '../transaction/transaction_record.dart';
import '../transaction/transaction_type.dart';
import 'credit_card_installment_repository.dart';

class InstallmentPlanScheduleSnapshot {
  const InstallmentPlanScheduleSnapshot({required this.plan, required this.scheduleItems});

  final InstallmentPlanRecord plan;
  final List<InstallmentScheduleItemRecord> scheduleItems;

  InstallmentScheduleItemRecord? get nextDueItem {
    final candidates = scheduleItems.where((item) => item.status == InstallmentScheduleItemStatus.pending || item.status == InstallmentScheduleItemStatus.billed).toList()
      ..sort((a, b) => a.periodNumber.compareTo(b.periodNumber));
    return candidates.isEmpty ? null : candidates.first;
  }

  String? get sourceTransactionId => plan.sourceTransactionId?.trim().isEmpty ?? true ? null : plan.sourceTransactionId;
}

class CreditCardDueAccountSummary {
  const CreditCardDueAccountSummary({
    required this.card,
    required this.generalPurchaseDue,
    required this.installmentDue,
    required this.installmentPrincipalDue,
    required this.installmentFeeDue,
    required this.excludedInstallmentSourceAmount,
    required this.minimumDue,
    required this.revolvingInterestDue,
    required this.lateFeeDue,
    required this.generalTransactions,
    required this.excludedInstallmentSourceTransactions,
    required this.installmentPlans,
  });

  final AccountRecord card;
  final double generalPurchaseDue;
  final double installmentDue;
  final double installmentPrincipalDue;
  final double installmentFeeDue;
  final double excludedInstallmentSourceAmount;
  final double minimumDue;
  final double revolvingInterestDue;
  final double lateFeeDue;
  final List<TransactionRecord> generalTransactions;
  final List<TransactionRecord> excludedInstallmentSourceTransactions;
  final List<InstallmentPlanScheduleSnapshot> installmentPlans;

  double get totalDue => card.currency.roundAmount(generalPurchaseDue + installmentDue + revolvingInterestDue + lateFeeDue);
  double get totalDueTwd => totalDue * card.currency.defaultRateToTwd;
  double get minimumDueTwd => minimumDue * card.currency.defaultRateToTwd;
  double get installmentDueTwd => installmentDue * card.currency.defaultRateToTwd;
  double get generalPurchaseDueTwd => generalPurchaseDue * card.currency.defaultRateToTwd;
  double get excludedInstallmentSourceAmountTwd => excludedInstallmentSourceAmount * card.currency.defaultRateToTwd;
}

class CreditCardDueSummary {
  const CreditCardDueSummary({required this.accounts});

  final List<CreditCardDueAccountSummary> accounts;

  int get cardCount => accounts.length;
  double get totalDueTwd => accounts.fold<double>(0, (sum, item) => sum + item.totalDueTwd);
  double get minimumDueTwd => accounts.fold<double>(0, (sum, item) => sum + item.minimumDueTwd);
  double get installmentDueTwd => accounts.fold<double>(0, (sum, item) => sum + item.installmentDueTwd);
  double get generalPurchaseDueTwd => accounts.fold<double>(0, (sum, item) => sum + item.generalPurchaseDueTwd);
  double get excludedInstallmentSourceAmountTwd => accounts.fold<double>(0, (sum, item) => sum + item.excludedInstallmentSourceAmountTwd);
}

class LoanDueAccountSummary {
  const LoanDueAccountSummary({
    required this.loan,
    required this.principalDue,
    required this.interestDue,
    required this.totalDue,
    required this.rows,
  });

  final AccountRecord loan;
  final double principalDue;
  final double interestDue;
  final double totalDue;
  final List<LoanDueScheduleRow> rows;

  double get principalDueTwd => principalDue * loan.currency.defaultRateToTwd;
  double get interestDueTwd => interestDue * loan.currency.defaultRateToTwd;
  double get totalDueTwd => totalDue * loan.currency.defaultRateToTwd;
}

class LoanDueSummary {
  const LoanDueSummary({required this.accounts});

  final List<LoanDueAccountSummary> accounts;

  int get loanCount => accounts.length;
  double get totalDueTwd => accounts.fold<double>(0, (sum, item) => sum + item.totalDueTwd);
  double get principalDueTwd => accounts.fold<double>(0, (sum, item) => sum + item.principalDueTwd);
  double get interestDueTwd => accounts.fold<double>(0, (sum, item) => sum + item.interestDueTwd);
}

class LoanDueScheduleRow {
  const LoanDueScheduleRow({
    required this.periodNumber,
    required this.dueDate,
    required this.principal,
    required this.interest,
    required this.total,
    required this.remainingPrincipal,
    required this.isPaid,
  });

  final int periodNumber;
  final DateTime dueDate;
  final double principal;
  final double interest;
  final double total;
  final double remainingPrincipal;
  final bool isPaid;

  String get paymentNote => isPaid ? '已繳納' : '未繳納';
}

class PlanDueSummary {
  const PlanDueSummary({required this.creditCard, required this.loan});

  final CreditCardDueSummary creditCard;
  final LoanDueSummary loan;
}

PlanDueSummary buildPlanDueSummary({
  required List<AccountRecord> accounts,
  required List<TransactionRecord> transactions,
  required List<InstallmentPlanScheduleSnapshot> installmentPlans,
}) {
  final activeAccounts = accounts.where((account) => !account.isArchived).toList();
  return PlanDueSummary(
    creditCard: buildCreditCardDueSummary(
      creditCards: activeAccounts.where((account) => account.type == AccountType.creditCard).toList(),
      transactions: transactions,
      installmentPlans: installmentPlans,
    ),
    loan: buildLoanDueSummary(
      loans: activeAccounts.where((account) => account.type == AccountType.loan).toList(),
      transactions: transactions,
    ),
  );
}

CreditCardDueSummary buildCreditCardDueSummary({
  required List<AccountRecord> creditCards,
  required List<TransactionRecord> transactions,
  required List<InstallmentPlanScheduleSnapshot> installmentPlans,
}) {
  final sourceTransactionIds = installmentPlans.map((item) => item.sourceTransactionId).whereType<String>().toSet();
  final accounts = <CreditCardDueAccountSummary>[];
  for (final card in creditCards) {
    final cardInstallments = installmentPlans.where((item) => item.plan.cardId == card.id && item.plan.status == InstallmentPlanStatus.active).toList();
    final excludedTransactions = transactions.where((tx) => sourceTransactionIds.contains(tx.id) && tx.accountName == card.displayName).toList();
    final generalTransactions = transactions.where((tx) => _isCardPurchase(tx, card) && !sourceTransactionIds.contains(tx.id)).toList();
    final generalPurchaseDue = card.currency.roundAmount(generalTransactions.fold<double>(0, (sum, tx) => sum + _toAccountCurrency(tx, card)));
    final excludedAmount = card.currency.roundAmount(excludedTransactions.fold<double>(0, (sum, tx) => sum + _toAccountCurrency(tx, card)));
    var installmentDue = 0.0;
    var installmentPrincipalDue = 0.0;
    var installmentFeeDue = 0.0;
    for (final plan in cardInstallments) {
      final nextDue = plan.nextDueItem;
      if (nextDue == null) continue;
      installmentDue += nextDue.totalPayment;
      installmentPrincipalDue += nextDue.principal;
      installmentFeeDue += nextDue.fee;
    }
    installmentDue = card.currency.roundAmount(installmentDue);
    installmentPrincipalDue = card.currency.roundAmount(installmentPrincipalDue);
    installmentFeeDue = card.currency.roundAmount(installmentFeeDue);
    final subtotal = card.currency.roundAmount(generalPurchaseDue + installmentDue);
    final minimumDue = _estimateMinimumDue(card, subtotal);
    accounts.add(
      CreditCardDueAccountSummary(
        card: card,
        generalPurchaseDue: generalPurchaseDue,
        installmentDue: installmentDue,
        installmentPrincipalDue: installmentPrincipalDue,
        installmentFeeDue: installmentFeeDue,
        excludedInstallmentSourceAmount: excludedAmount,
        minimumDue: minimumDue,
        revolvingInterestDue: 0,
        lateFeeDue: 0,
        generalTransactions: List.unmodifiable(generalTransactions),
        excludedInstallmentSourceTransactions: List.unmodifiable(excludedTransactions),
        installmentPlans: List.unmodifiable(cardInstallments),
      ),
    );
  }
  return CreditCardDueSummary(accounts: List.unmodifiable(accounts));
}

LoanDueSummary buildLoanDueSummary({required List<AccountRecord> loans, List<TransactionRecord> transactions = const <TransactionRecord>[]}) {
  final accounts = loans.map((loan) {
    final rows = buildLoanDueScheduleRows(
      loan,
      transactions: transactions,
      maxRows: math.min(loan.loanTermMonths <= 0 ? 1 : loan.loanTermMonths, 12),
    );
    final first = rows.isEmpty
        ? LoanDueScheduleRow(
            periodNumber: 1,
            dueDate: DateTime.now(),
            principal: 0,
            interest: 0,
            total: 0,
            remainingPrincipal: loan.loanPrincipal,
            isPaid: false,
          )
        : rows.first;
    return LoanDueAccountSummary(
      loan: loan,
      principalDue: first.principal,
      interestDue: first.interest,
      totalDue: first.total,
      rows: List.unmodifiable(rows),
    );
  }).toList();
  return LoanDueSummary(accounts: List.unmodifiable(accounts));
}

List<LoanDueScheduleRow> buildLoanDueScheduleRows(AccountRecord loan, {List<TransactionRecord> transactions = const <TransactionRecord>[], int maxRows = 12}) {
  if (!loan.isLoan || loan.loanPrincipal <= 0 || loan.loanTermMonths <= 0 || maxRows <= 0) return const [];
  final paidAmount = _loanPaidAmount(loan, transactions);
  var cumulativeDue = 0.0;
  final rows = <LoanDueScheduleRow>[];
  var remaining = loan.currency.roundAmount(loan.loanPrincipal);
  final r = loan.monthlyInterestRate;
  final dueDay = loan.loanPaymentDueDay.clamp(1, 28).toInt();
  final start = loan.loanStartDate ?? DateTime.now();
  final fixedPayment = loan.estimatedMonthlyPayment;
  for (var i = 1; i <= math.min(maxRows, loan.loanTermMonths); i++) {
    final interest = loan.currency.roundAmount(remaining * r);
    double principal;
    switch (loan.loanRepaymentMethod) {
      case LoanRepaymentMethod.principalOnly:
        principal = loan.currency.roundAmount(loan.loanPrincipal / loan.loanTermMonths);
      case LoanRepaymentMethod.interestOnly:
        principal = i == loan.loanTermMonths ? remaining : 0;
      case LoanRepaymentMethod.equalPrincipalAndInterest:
        principal = loan.currency.roundAmount(fixedPayment - interest);
    }
    principal = loan.currency.roundAmount(principal.clamp(0, remaining).toDouble());
    final total = loan.currency.roundAmount(principal + interest);
    cumulativeDue = loan.currency.roundAmount(cumulativeDue + total);
    remaining = loan.currency.roundAmount(math.max(0, remaining - principal));
    rows.add(
      LoanDueScheduleRow(
        periodNumber: i,
        dueDate: DateTime(start.year, start.month + i, dueDay),
        principal: principal,
        interest: interest,
        total: total,
        remainingPrincipal: remaining,
        isPaid: paidAmount + 0.0001 >= cumulativeDue,
      ),
    );
  }
  return List.unmodifiable(rows);
}

bool _isCardPurchase(TransactionRecord tx, AccountRecord card) {
  return tx.type == TransactionType.expense && tx.accountName == card.displayName;
}

double _loanPaidAmount(AccountRecord loan, List<TransactionRecord> transactions) {
  final matches = transactions.where((tx) {
    final touchesLoan = tx.accountName == loan.displayName || tx.fromAccountName == loan.displayName || tx.toAccountName == loan.displayName;
    if (!touchesLoan) return false;
    if (tx.isLoanRepayment) return true;
    if (tx.type == TransactionType.loan && tx.category.contains('還款')) return true;
    return tx.category.contains('還款') || tx.note.contains('還款');
  });
  return loan.currency.roundAmount(matches.fold<double>(0, (sum, tx) => sum + _toAccountCurrency(tx, loan)));
}

double _toAccountCurrency(TransactionRecord tx, AccountRecord account) {
  if (tx.currency == account.currency) return tx.currency.roundAmount(tx.amount);
  final txRate = tx.exchangeRateToBase == 0 ? tx.currency.defaultRateToTwd : tx.exchangeRateToBase;
  final accountRate = account.currency.defaultRateToTwd == 0 ? 1.0 : account.currency.defaultRateToTwd;
  return account.currency.roundAmount(tx.amount * txRate / accountRate);
}

double _estimateMinimumDue(AccountRecord card, double totalDue) {
  if (totalDue <= 0) return 0;
  final percentage = card.currency.roundAmount(totalDue * 0.10);
  final floor = card.currency == CurrencyCode.twd ? 1000.0 : 0.0;
  return card.currency.roundAmount(math.min(totalDue, math.max(percentage, floor)));
}
