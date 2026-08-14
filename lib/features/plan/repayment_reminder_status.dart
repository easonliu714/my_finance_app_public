import '../account/account_record.dart';

class RepaymentReminderStatus {
  const RepaymentReminderStatus({
    required this.dueDate,
    required this.daysUntilDue,
    required this.label,
    required this.isOverdue,
    required this.isDueSoon,
    this.isCompleted = false,
  });

  final DateTime dueDate;
  final int daysUntilDue;
  final String label;
  final bool isOverdue;
  final bool isDueSoon;
  final bool isCompleted;
}

RepaymentReminderStatus buildLoanReminderStatus(AccountRecord account, {DateTime? now, bool isCompleted = false}) {
  return _buildReminderStatus(
    dueDay: account.loanPaymentDueDay,
    reminderDaysBefore: account.loanReminderDaysBefore,
    enabled: account.loanReminderEnabled,
    now: now,
    isCompleted: isCompleted,
  );
}

RepaymentReminderStatus buildCreditCardReminderStatus(AccountRecord account, {DateTime? now, bool isCompleted = false}) {
  return _buildReminderStatus(
    dueDay: account.paymentDueDay,
    reminderDaysBefore: account.reminderDaysBefore,
    enabled: account.paymentReminderEnabled,
    now: now,
    isCompleted: isCompleted,
  );
}

RepaymentReminderStatus _buildReminderStatus({required int dueDay, required int reminderDaysBefore, required bool enabled, DateTime? now, bool isCompleted = false}) {
  final today = _dateOnly(now ?? DateTime.now());
  final safeDueDay = dueDay.clamp(1, 28).toInt();
  var dueDate = DateTime(today.year, today.month, safeDueDay);
  if (today.isAfter(dueDate)) {
    dueDate = DateTime(today.year, today.month + 1, safeDueDay);
  }
  final days = dueDate.difference(today).inDays;
  final reminderWindow = reminderDaysBefore.clamp(0, 31).toInt();
  final isDueSoon = enabled && !isCompleted && days >= 0 && days <= reminderWindow;
  final isOverdue = enabled && !isCompleted && today.isAfter(dueDate);
  final label = isCompleted
      ? '本期已完成'
      : !enabled
          ? '未啟用提醒'
          : isOverdue
              ? '已逾期 ${days.abs()} 天'
              : isDueSoon
                  ? '即將到期：$days 天'
                  : '距到期日 $days 天';
  return RepaymentReminderStatus(
    dueDate: dueDate,
    daysUntilDue: days,
    label: label,
    isOverdue: isOverdue,
    isDueSoon: isDueSoon,
    isCompleted: isCompleted,
  );
}

DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);
