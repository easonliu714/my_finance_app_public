import '../account/account_record.dart';
import '../transaction/transaction_record.dart';
import '../transaction/transaction_type.dart';
import 'credit_card_installment_repository.dart';

class InstallmentPaymentPreviewInput {
  const InstallmentPaymentPreviewInput({
    required this.plan,
    required this.scheduleItem,
    required this.paymentAccount,
    this.memberName = '自己',
    this.merchantName = '不使用商家',
    this.tagName = '信用卡分期',
    this.category = '信用卡分期付款',
    this.notePrefix = '信用卡分期付款',
    this.idPrefix = 'installment-payment-preview',
  });

  final InstallmentPlanRecord plan;
  final InstallmentScheduleItemRecord scheduleItem;
  final AccountRecord paymentAccount;
  final String memberName;
  final String merchantName;
  final String tagName;
  final String category;
  final String notePrefix;
  final String idPrefix;
}

class InstallmentPaymentPreviewResult {
  const InstallmentPaymentPreviewResult({
    required this.transaction,
    required this.planId,
    required this.scheduleItemId,
    required this.periodNumber,
    required this.isWriteSafePreview,
  });

  final TransactionRecord transaction;
  final String planId;
  final String scheduleItemId;
  final int periodNumber;
  final bool isWriteSafePreview;
}

class InstallmentPaymentPreviewBlocked implements Exception {
  const InstallmentPaymentPreviewBlocked(this.message);

  final String message;

  @override
  String toString() => message;
}

InstallmentPaymentPreviewResult buildInstallmentPaymentTransactionPreview(InstallmentPaymentPreviewInput input) {
  final plan = input.plan;
  final item = input.scheduleItem;
  if (item.planId != plan.id) {
    throw const InstallmentPaymentPreviewBlocked('Schedule item does not belong to the installment plan.');
  }
  if (plan.status != InstallmentPlanStatus.active) {
    throw const InstallmentPaymentPreviewBlocked('Only active installment plans can build payment previews.');
  }
  if (item.status != InstallmentScheduleItemStatus.pending && item.status != InstallmentScheduleItemStatus.billed) {
    throw const InstallmentPaymentPreviewBlocked('Only pending or billed schedule items can build payment previews.');
  }
  if (item.generatedTransactionId != null && item.generatedTransactionId!.trim().isNotEmpty) {
    throw const InstallmentPaymentPreviewBlocked('Schedule item already has a generated transaction.');
  }
  if (input.paymentAccount.type == AccountType.creditCard) {
    throw const InstallmentPaymentPreviewBlocked('Payment account cannot be a credit card account.');
  }
  final currency = plan.currency;
  final amount = currency.roundAmount(item.totalPayment);
  if (amount <= 0) {
    throw const InstallmentPaymentPreviewBlocked('Payment amount must be greater than zero.');
  }
  final transaction = TransactionRecord(
    id: '${input.idPrefix}-${plan.id}-${item.periodNumber}',
    type: TransactionType.expense,
    amount: amount,
    category: input.category,
    occurredAt: item.statementDate,
    accountName: input.paymentAccount.displayName,
    memberName: input.memberName,
    merchantName: input.merchantName,
    tagName: input.tagName,
    note: '${input.notePrefix}：${plan.cardNameSnapshot} 第 ${item.periodNumber}/${plan.termCount} 期；plan=${plan.id}; schedule=${item.id}',
    currency: currency,
    exchangeRateToBase: currency.defaultRateToTwd,
  );
  return InstallmentPaymentPreviewResult(
    transaction: transaction,
    planId: plan.id,
    scheduleItemId: item.id,
    periodNumber: item.periodNumber,
    isWriteSafePreview: true,
  );
}
