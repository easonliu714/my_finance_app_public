import 'package:uuid/uuid.dart';

import '../account/account_record.dart';
import '../transaction/transaction_record.dart';
import '../transaction/transaction_type.dart';

class LoanDisbursementPlan {
  const LoanDisbursementPlan({
    required this.loan,
    required this.targetAccount,
    required this.groupId,
    required this.disbursementDate,
    required this.records,
  });

  final AccountRecord loan;
  final AccountRecord targetAccount;
  final String groupId;
  final DateTime disbursementDate;
  final List<TransactionRecord> records;

  double get grossPrincipal => loan.currency.roundAmount(loan.loanPrincipal);
  double get handlingFee => loan.currency.roundAmount(loan.loanHandlingFee);
  double get netReceived => loan.currency.roundAmount(grossPrincipal - handlingFee);
}

LoanDisbursementPlan? buildLoanDisbursementPlan({
  required AccountRecord loan,
  required List<AccountRecord> accounts,
  String? groupId,
}) {
  if (!loan.isLoan) return null;
  if (loan.loanPrincipal <= 0) return null;
  final targetName = loan.loanDisbursementAccountName.trim();
  if (targetName.isEmpty) return null;
  AccountRecord? targetAccount;
  for (final account in accounts) {
    if (account.displayName == targetName && !account.isArchived) {
      targetAccount = account;
      break;
    }
  }
  if (targetAccount == null) return null;

  final disbursementDate = loan.loanStartDate ?? DateTime.now();
  final resolvedGroupId = groupId ?? 'loan-disbursement-${loan.id}-${const Uuid().v4()}';
  final principal = loan.currency.roundAmount(loan.loanPrincipal);
  final fee = loan.currency.roundAmount(loan.loanHandlingFee.clamp(0, loan.loanPrincipal).toDouble());
  final noteSuffix = '借貸撥款 ${loan.displayName}';
  final records = <TransactionRecord>[
    TransactionRecord(
      id: '$resolvedGroupId-principal',
      type: TransactionType.income,
      amount: principal,
      category: '借貸撥款',
      occurredAt: disbursementDate,
      accountName: targetAccount.displayName,
      memberName: '自己',
      merchantName: loan.displayName,
      tagName: '借貸',
      note: '$noteSuffix・本金入帳',
      currency: loan.currency,
      exchangeRateToBase: loan.currency.defaultRateToTwd,
      repaymentGroupId: resolvedGroupId,
    ),
  ];
  if (fee > 0) {
    records.add(
      TransactionRecord(
        id: '$resolvedGroupId-fee',
        type: TransactionType.expense,
        amount: fee,
        category: '借貸手續費',
        occurredAt: disbursementDate,
        accountName: targetAccount.displayName,
        memberName: '自己',
        merchantName: loan.displayName,
        tagName: '借貸',
        note: '$noteSuffix・手續費支出',
        currency: loan.currency,
        exchangeRateToBase: loan.currency.defaultRateToTwd,
        repaymentGroupId: resolvedGroupId,
      ),
    );
  }

  return LoanDisbursementPlan(
    loan: loan,
    targetAccount: targetAccount,
    groupId: resolvedGroupId,
    disbursementDate: disbursementDate,
    records: records,
  );
}
