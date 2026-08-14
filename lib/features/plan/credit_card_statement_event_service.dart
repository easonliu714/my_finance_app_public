import 'credit_card_minimum_payment_service.dart';
import 'credit_card_revolving_interest_service.dart';
import 'credit_card_statement_event.dart';
import 'credit_card_statement_service.dart';

CreditCardStatementEvent buildCreditCardStatementEventSnapshot(
  CreditCardStatementEstimate statementEstimate, {
  CreditCardMinimumPaymentEstimate? minimumPaymentEstimate,
  CreditCardRevolvingInterestEstimate? revolvingInterestEstimate,
  double? paidAmountOverride,
  String note = '',
  DateTime? now,
}) {
  final card = statementEstimate.card;
  final minimum = minimumPaymentEstimate ?? buildCreditCardMinimumPaymentEstimate(statementEstimate);
  final revolving = revolvingInterestEstimate ?? buildCreditCardRevolvingInterestEstimate(minimum);
  final paidAmount = card.currency.roundAmount(paidAmountOverride ?? statementEstimate.paymentTotal);
  final totalBalance = card.currency.roundAmount(statementEstimate.outstandingTotal);
  final unpaidBalance = card.currency.roundAmount((totalBalance - paidAmount).clamp(0, double.infinity).toDouble());
  final timestamp = now ?? DateTime.now();
  final id = 'statement-${card.id}-${_dateKey(statementEstimate.periodEnd)}';

  return CreditCardStatementEvent(
    id: id,
    cardId: card.id,
    cardName: card.displayName,
    currency: card.currency,
    statementDate: statementEstimate.periodEnd,
    dueDate: statementEstimate.dueDate,
    periodStart: statementEstimate.periodStart,
    periodEnd: statementEstimate.periodEnd,
    totalBalance: totalBalance,
    minimumPayment: minimum.estimatedMinimumDue,
    paidAmount: paidAmount,
    unpaidBalance: unpaidBalance,
    estimatedRevolvingInterest: revolving.estimatedCycleInterest,
    estimatedLateFee: revolving.estimatedLateFee,
    note: note.trim().isEmpty ? '由計劃頁估算建立的帳單快照，實際金額請依銀行帳單校正。' : note.trim(),
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

String _dateKey(DateTime value) {
  return '${value.year}${value.month.toString().padLeft(2, '0')}${value.day.toString().padLeft(2, '0')}';
}
