import '../account/account_record.dart';
import 'credit_card_statement_service.dart';
import 'loan_repayment_flow.dart';
import 'repayment_reminder_status.dart';

class RepaymentReminderScheduleItem {
  const RepaymentReminderScheduleItem({
    required this.id,
    required this.accountName,
    required this.kind,
    required this.title,
    required this.message,
    required this.dueDate,
    required this.notifyDate,
    required this.enabled,
    required this.isOverdue,
    required this.isDueSoon,
    required this.isCompleted,
  });

  final String id;
  final String accountName;
  final String kind;
  final String title;
  final String message;
  final DateTime dueDate;
  final DateTime notifyDate;
  final bool enabled;
  final bool isOverdue;
  final bool isDueSoon;
  final bool isCompleted;
}

List<RepaymentReminderScheduleItem> buildRepaymentReminderSchedule({
  required List<AccountRecord> creditCards,
  required List<CreditCardStatementEstimate> creditCardEstimates,
  required List<AccountRecord> loans,
  required Map<String, LoanPreviewRow?> nextLoanPaymentByAccountId,
  DateTime? now,
}) {
  final result = <RepaymentReminderScheduleItem>[];
  final today = _dateOnly(now ?? DateTime.now());
  for (final estimate in creditCardEstimates) {
    final card = estimate.card;
    final status = buildCreditCardReminderStatus(card, now: today, isCompleted: estimate.isPaid);
    result.add(RepaymentReminderScheduleItem(
      id: 'credit-card-${card.id}',
      accountName: card.displayName,
      kind: '信用卡',
      title: '${card.displayName} 信用卡繳款',
      message: estimate.isPaid
          ? '本期已完成繳款。'
          : '估算應繳 ${_formatAmount(estimate.estimatedDue)} ${card.currency.code}，請以銀行帳單為準。',
      dueDate: status.dueDate,
      notifyDate: _dateOnly(status.dueDate.subtract(Duration(days: card.reminderDaysBefore.clamp(0, 31).toInt()))),
      enabled: card.paymentReminderEnabled,
      isOverdue: status.isOverdue,
      isDueSoon: status.isDueSoon,
      isCompleted: status.isCompleted,
    ));
  }
  for (final loan in loans) {
    final nextPayment = nextLoanPaymentByAccountId[loan.id];
    final completed = nextPayment == null && loan.loanPrincipal > 0;
    final status = buildLoanReminderStatus(loan, now: today, isCompleted: completed);
    result.add(RepaymentReminderScheduleItem(
      id: 'loan-${loan.id}',
      accountName: loan.displayName,
      kind: '借貸',
      title: '${loan.displayName} 借貸還款',
      message: completed
          ? '借貸期數已完成。'
          : nextPayment == null
              ? '尚無可試算的下一期還款。'
              : '下一期第 ${nextPayment.period} 期，預估 ${_formatAmount(nextPayment.payment)} ${loan.currency.code}。',
      dueDate: status.dueDate,
      notifyDate: _dateOnly(status.dueDate.subtract(Duration(days: loan.loanReminderDaysBefore.clamp(0, 31).toInt()))),
      enabled: loan.loanReminderEnabled,
      isOverdue: status.isOverdue,
      isDueSoon: status.isDueSoon,
      isCompleted: status.isCompleted,
    ));
  }
  result.sort((a, b) => a.dueDate.compareTo(b.dueDate));
  return result;
}

DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);
String _formatAmount(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
