import 'package:uuid/uuid.dart';

import '../account/account_record.dart';
import '../transaction/transaction_record.dart';
import '../transaction/transaction_type.dart';
import 'credit_card_installment_repository.dart';
import 'credit_card_installment_service.dart';

class SourceTransactionInstallmentEligibility {
  const SourceTransactionInstallmentEligibility._({required this.isEligible, required this.message});

  const SourceTransactionInstallmentEligibility.allowed() : this._(isEligible: true, message: '可建立信用卡消費分期。');

  const SourceTransactionInstallmentEligibility.blocked(String message) : this._(isEligible: false, message: message);

  final bool isEligible;
  final String message;
}

SourceTransactionInstallmentEligibility checkSourceTransactionInstallmentEligibility({
  required TransactionRecord transaction,
  required AccountRecord card,
}) {
  if (transaction.type != TransactionType.expense) {
    return const SourceTransactionInstallmentEligibility.blocked('只有支出交易可以轉為信用卡分期。');
  }
  if (card.type != AccountType.creditCard) {
    return const SourceTransactionInstallmentEligibility.blocked('分期來源帳戶必須是信用卡帳戶。');
  }
  if (transaction.accountName != card.displayName) {
    return const SourceTransactionInstallmentEligibility.blocked('交易帳戶與信用卡帳戶不一致。');
  }
  if (transaction.amount <= 0) {
    return const SourceTransactionInstallmentEligibility.blocked('交易金額必須大於 0。');
  }
  return const SourceTransactionInstallmentEligibility.allowed();
}

CreditCardInstallmentPlanInput buildSourceTransactionInstallmentInput({
  required TransactionRecord transaction,
  required AccountRecord card,
  required int termCount,
  required DateTime firstStatementDate,
  CreditCardInstallmentFeeMode feeMode = CreditCardInstallmentFeeMode.totalFee,
  double totalFee = 0,
  double annualRate = 0,
  CreditCardInstallmentRemainderPolicy remainderPolicy = CreditCardInstallmentRemainderPolicy.firstPeriod,
  DateTime? applicationDate,
  String note = '',
  String? id,
}) {
  final eligibility = checkSourceTransactionInstallmentEligibility(transaction: transaction, card: card);
  if (!eligibility.isEligible) {
    throw ArgumentError(eligibility.message);
  }
  return CreditCardInstallmentPlanInput(
    id: id ?? 'source-tx-${const Uuid().v4()}',
    scenario: CreditCardInstallmentScenario.purchaseTime,
    cardId: card.id,
    cardName: card.displayName,
    currency: transaction.currency,
    principal: transaction.amount,
    termCount: termCount,
    firstStatementDate: firstStatementDate,
    sourceTransactionId: transaction.id,
    applicationDate: applicationDate ?? DateTime.now(),
    feeMode: feeMode,
    totalFee: totalFee,
    annualRate: annualRate,
    remainderPolicy: remainderPolicy,
    originalUnpaidBalance: 0,
    note: note.isEmpty ? 'source transaction installment: ${transaction.id}' : note,
  );
}

Future<InstallmentPlanRecord> createInstallmentPlanFromSourceTransaction({
  required CreditCardInstallmentRepository repository,
  required TransactionRecord transaction,
  required AccountRecord card,
  required int termCount,
  required DateTime firstStatementDate,
  CreditCardInstallmentFeeMode feeMode = CreditCardInstallmentFeeMode.totalFee,
  double totalFee = 0,
  double annualRate = 0,
  CreditCardInstallmentRemainderPolicy remainderPolicy = CreditCardInstallmentRemainderPolicy.firstPeriod,
  DateTime? applicationDate,
  String note = '',
  String? id,
}) async {
  final input = buildSourceTransactionInstallmentInput(
    transaction: transaction,
    card: card,
    termCount: termCount,
    firstStatementDate: firstStatementDate,
    feeMode: feeMode,
    totalFee: totalFee,
    annualRate: annualRate,
    remainderPolicy: remainderPolicy,
    applicationDate: applicationDate,
    note: note,
    id: id,
  );
  final duplicate = await repository.findActivePlanBySourceTransactionId(transaction.id);
  if (duplicate != null) {
    throw DuplicateInstallmentSourceFailure('Source transaction ${transaction.id} already has an active installment plan.');
  }
  final schedule = buildCreditCardInstallmentSchedule(input);
  return repository.createPlan(input: input, schedule: schedule);
}
