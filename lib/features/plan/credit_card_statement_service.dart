import '../account/account_record.dart';
import '../transaction/transaction_record.dart';
import '../transaction/transaction_type.dart';

class CreditCardStatementEstimate {
  const CreditCardStatementEstimate({
    required this.card,
    required this.periodStart,
    required this.periodEnd,
    required this.dueDate,
    required this.purchaseTotal,
    required this.paymentTotal,
    required this.estimatedDue,
    required this.outstandingTotal,
    required this.totalPurchaseCount,
    required this.totalPaymentCount,
    required this.isPaid,
    required this.purchaseCount,
    required this.paymentCount,
  });

  final AccountRecord card;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime dueDate;
  final double purchaseTotal;
  final double paymentTotal;
  final double estimatedDue;
  final double outstandingTotal;
  final int totalPurchaseCount;
  final int totalPaymentCount;
  final bool isPaid;
  final int purchaseCount;
  final int paymentCount;

  String get periodLabel => '${_formatDate(periodStart)} - ${_formatDate(periodEnd)}';
}

CreditCardStatementEstimate buildCreditCardStatementEstimate(AccountRecord card, List<TransactionRecord> transactions, {DateTime? now}) {
  final today = _dateOnly(now ?? DateTime.now());
  final statementDay = card.statementDay.clamp(1, 28).toInt();
  final paymentDueDay = card.paymentDueDay.clamp(1, 28).toInt();
  final currentCutoff = DateTime(today.year, today.month, statementDay);
  final periodEnd = today.isAfter(currentCutoff) || _sameDay(today, currentCutoff) ? currentCutoff : DateTime(today.year, today.month - 1, statementDay);
  final periodStart = DateTime(periodEnd.year, periodEnd.month - 1, statementDay + 1);
  var dueDate = DateTime(periodEnd.year, periodEnd.month, paymentDueDay);
  if (!dueDate.isAfter(periodEnd)) {
    dueDate = DateTime(periodEnd.year, periodEnd.month + 1, paymentDueDay);
  }

  var purchaseTotal = 0.0;
  var paymentTotal = 0.0;
  var outstandingPurchaseTotal = 0.0;
  var outstandingPaymentTotal = 0.0;
  var purchaseCount = 0;
  var paymentCount = 0;
  var totalPurchaseCount = 0;
  var totalPaymentCount = 0;
  for (final tx in transactions) {
    final occurred = _dateOnly(tx.occurredAt);
    final inStatementPeriod = !occurred.isBefore(periodStart) && !occurred.isAfter(periodEnd);
    final inPaymentWindow = occurred.isAfter(periodEnd) && !occurred.isAfter(dueDate);
    final isCardExpense = tx.type == TransactionType.expense && tx.accountName == card.displayName;
    final isPayment = tx.type == TransactionType.transfer && tx.toAccountName == card.displayName && tx.category == '信用卡繳款';
    if (isCardExpense) {
      final amount = _toCardCurrency(tx, card);
      if (!occurred.isAfter(today)) {
        outstandingPurchaseTotal += amount;
        totalPurchaseCount += 1;
      }
      if (inStatementPeriod) {
        purchaseTotal += amount;
        purchaseCount += 1;
      }
    }
    if (isPayment) {
      final amount = _toCardCurrency(tx, card);
      if (!occurred.isAfter(today)) {
        outstandingPaymentTotal += amount;
        totalPaymentCount += 1;
      }
      if (inPaymentWindow) {
        paymentTotal += amount;
        paymentCount += 1;
      }
    }
  }
  purchaseTotal = card.currency.roundAmount(purchaseTotal);
  paymentTotal = card.currency.roundAmount(paymentTotal);
  final outstandingTotal = card.currency.roundAmount((outstandingPurchaseTotal - outstandingPaymentTotal).clamp(0, double.infinity).toDouble());
  final estimatedDue = outstandingTotal;
  return CreditCardStatementEstimate(
    card: card,
    periodStart: periodStart,
    periodEnd: periodEnd,
    dueDate: dueDate,
    purchaseTotal: purchaseTotal,
    paymentTotal: paymentTotal,
    estimatedDue: estimatedDue,
    outstandingTotal: outstandingTotal,
    totalPurchaseCount: totalPurchaseCount,
    totalPaymentCount: totalPaymentCount,
    isPaid: outstandingPurchaseTotal > 0 && outstandingTotal <= 0,
    purchaseCount: purchaseCount,
    paymentCount: paymentCount,
  );
}

double _toCardCurrency(TransactionRecord tx, AccountRecord card) {
  if (tx.currency == card.currency) return tx.currency.roundAmount(tx.amount);
  final txRate = tx.exchangeRateToBase == 0 ? tx.currency.defaultRateToTwd : tx.exchangeRateToBase;
  final cardRate = card.currency.defaultRateToTwd == 0 ? 1.0 : card.currency.defaultRateToTwd;
  return card.currency.roundAmount(tx.amount * txRate / cardRate);
}

DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);
bool _sameDay(DateTime left, DateTime right) => left.year == right.year && left.month == right.month && left.day == right.day;
String _formatDate(DateTime value) => '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
