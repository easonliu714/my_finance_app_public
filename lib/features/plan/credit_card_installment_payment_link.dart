import '../transaction/transaction_record.dart';

class CreditCardInstallmentPaymentLink {
  const CreditCardInstallmentPaymentLink({
    required this.planId,
    required this.scheduleItemId,
    required this.generatedTransactionId,
  });

  final String planId;
  final String scheduleItemId;
  final String generatedTransactionId;
}

CreditCardInstallmentPaymentLink? parseCreditCardInstallmentPaymentLink(TransactionRecord record) {
  final isInstallmentPayment = record.category == '信用卡分期付款' || record.tagName == '信用卡分期';
  if (!isInstallmentPayment) return null;
  final planId = _extractNoteToken(record.note, 'plan');
  final scheduleItemId = _extractNoteToken(record.note, 'schedule');
  if (planId == null || scheduleItemId == null || record.id.trim().isEmpty) return null;
  return CreditCardInstallmentPaymentLink(
    planId: planId,
    scheduleItemId: scheduleItemId,
    generatedTransactionId: record.id.trim(),
  );
}

String? _extractNoteToken(String note, String key) {
  final match = RegExp('(?:^|[;；\\s])$key=([^;；\\s]+)').firstMatch(note);
  final value = match?.group(1)?.trim();
  return value == null || value.isEmpty ? null : value;
}
