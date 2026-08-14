import 'credit_card_installment_repository.dart';

class GeneratedInstallmentTransactionGuardInput {
  const GeneratedInstallmentTransactionGuardInput({
    required this.scheduleItem,
    required this.generatedTransactionId,
  });

  final InstallmentScheduleItemRecord scheduleItem;
  final String generatedTransactionId;
}

class GeneratedInstallmentTransactionGuardResult {
  const GeneratedInstallmentTransactionGuardResult({
    required this.updatedScheduleItem,
    required this.previousStatus,
    required this.nextStatus,
    required this.generatedTransactionId,
    required this.isPersistencePreview,
  });

  final InstallmentScheduleItemRecord updatedScheduleItem;
  final InstallmentScheduleItemStatus previousStatus;
  final InstallmentScheduleItemStatus nextStatus;
  final String generatedTransactionId;
  final bool isPersistencePreview;
}

class GeneratedInstallmentTransactionBlocked implements Exception {
  const GeneratedInstallmentTransactionBlocked(this.message);

  final String message;

  @override
  String toString() => message;
}

GeneratedInstallmentTransactionGuardResult markScheduleItemGeneratedPreview(GeneratedInstallmentTransactionGuardInput input) {
  final item = input.scheduleItem;
  final txId = input.generatedTransactionId.trim();
  if (txId.isEmpty) {
    throw const GeneratedInstallmentTransactionBlocked('Generated transaction id is required.');
  }
  if (item.generatedTransactionId != null && item.generatedTransactionId!.trim().isNotEmpty) {
    throw const GeneratedInstallmentTransactionBlocked('Schedule item already has a generated transaction id.');
  }
  if (item.status == InstallmentScheduleItemStatus.paid) {
    throw const GeneratedInstallmentTransactionBlocked('Paid schedule item cannot be generated again.');
  }
  if (item.status == InstallmentScheduleItemStatus.cancelled) {
    throw const GeneratedInstallmentTransactionBlocked('Cancelled schedule item cannot generate a transaction.');
  }
  if (item.totalPayment <= 0) {
    throw const GeneratedInstallmentTransactionBlocked('Schedule item payment amount must be greater than zero.');
  }
  final nextStatus = item.status == InstallmentScheduleItemStatus.pending ? InstallmentScheduleItemStatus.billed : item.status;
  return GeneratedInstallmentTransactionGuardResult(
    updatedScheduleItem: item.copyWith(generatedTransactionId: txId, status: nextStatus),
    previousStatus: item.status,
    nextStatus: nextStatus,
    generatedTransactionId: txId,
    isPersistencePreview: true,
  );
}

bool canHardCancelScheduleItem(InstallmentScheduleItemRecord item) {
  if (item.generatedTransactionId != null && item.generatedTransactionId!.trim().isNotEmpty) return false;
  return item.status == InstallmentScheduleItemStatus.pending || item.status == InstallmentScheduleItemStatus.billed;
}
