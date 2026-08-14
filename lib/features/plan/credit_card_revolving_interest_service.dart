import '../account/account_record.dart';
import 'credit_card_minimum_payment_service.dart';

class CreditCardLateFeeTier {
  const CreditCardLateFeeTier({
    required this.missedMinimumPaymentCount,
    required this.amount,
  });

  final int missedMinimumPaymentCount;
  final double amount;
}

class CreditCardRevolvingInterestRule {
  const CreditCardRevolvingInterestRule({
    required this.name,
    required this.annualInterestRate,
    required this.daysInYear,
    required this.estimatedCycleDays,
    required this.lateFeeTiers,
    required this.lateFeeWaiveThreshold,
    required this.disclaimer,
  });

  factory CreditCardRevolvingInterestRule.defaultEstimate(CurrencyCode currency) {
    return CreditCardRevolvingInterestRule(
      name: '預設循環信用估算規則',
      annualInterestRate: 0.15,
      daysInYear: 365,
      estimatedCycleDays: 30,
      lateFeeTiers: currency == CurrencyCode.twd
          ? const [
              CreditCardLateFeeTier(missedMinimumPaymentCount: 1, amount: 300),
              CreditCardLateFeeTier(missedMinimumPaymentCount: 2, amount: 400),
              CreditCardLateFeeTier(missedMinimumPaymentCount: 3, amount: 500),
            ]
          : const [],
      lateFeeWaiveThreshold: 0,
      disclaimer: '循環利息與違約金為估算值，銀行可能依實際入帳日、逐筆消費起息日、前期未清償金額、費用、利率級距與帳單條款調整，請以銀行帳單為準。',
    );
  }

  final String name;
  final double annualInterestRate;
  final int daysInYear;
  final int estimatedCycleDays;
  final List<CreditCardLateFeeTier> lateFeeTiers;
  final double lateFeeWaiveThreshold;
  final String disclaimer;
}

class CreditCardRevolvingInterestEstimate {
  const CreditCardRevolvingInterestEstimate({
    required this.card,
    required this.minimumPaymentEstimate,
    required this.rule,
    required this.assumedPaymentAmount,
    required this.revolvingPrincipal,
    required this.estimatedDailyInterest,
    required this.estimatedCycleInterest,
    required this.minimumPaymentShortfall,
    required this.estimatedLateFee,
    required this.hasRevolvingPrincipal,
    required this.hasLateFeeRisk,
  });

  final AccountRecord card;
  final CreditCardMinimumPaymentEstimate minimumPaymentEstimate;
  final CreditCardRevolvingInterestRule rule;
  final double assumedPaymentAmount;
  final double revolvingPrincipal;
  final double estimatedDailyInterest;
  final double estimatedCycleInterest;
  final double minimumPaymentShortfall;
  final double estimatedLateFee;
  final bool hasRevolvingPrincipal;
  final bool hasLateFeeRisk;

  double get estimatedNextCycleCost => estimatedCycleInterest + estimatedLateFee;
}

CreditCardRevolvingInterestEstimate buildCreditCardRevolvingInterestEstimate(
  CreditCardMinimumPaymentEstimate minimumPaymentEstimate, {
  CreditCardRevolvingInterestRule? rule,
  double? assumedPaymentAmount,
  int missedMinimumPaymentCount = 1,
}) {
  final card = minimumPaymentEstimate.card;
  final activeRule = rule ?? CreditCardRevolvingInterestRule.defaultEstimate(card.currency);
  final outstandingTotal = minimumPaymentEstimate.statementEstimate.outstandingTotal.clamp(0, double.infinity).toDouble();
  final paymentAmount = card.currency.roundAmount((assumedPaymentAmount ?? minimumPaymentEstimate.estimatedMinimumDue).clamp(0, double.infinity).toDouble());
  final revolvingPrincipal = card.currency.roundAmount((outstandingTotal - paymentAmount).clamp(0, double.infinity).toDouble());
  final dailyInterest = activeRule.daysInYear <= 0 ? 0.0 : card.currency.roundAmount(revolvingPrincipal * activeRule.annualInterestRate / activeRule.daysInYear);
  final cycleInterest = card.currency.roundAmount(dailyInterest * activeRule.estimatedCycleDays.clamp(0, 366));
  final minimumShortfall = card.currency.roundAmount((minimumPaymentEstimate.estimatedMinimumDue - paymentAmount).clamp(0, double.infinity).toDouble());
  final lateFee = minimumShortfall <= activeRule.lateFeeWaiveThreshold ? 0.0 : _lateFeeFor(activeRule, missedMinimumPaymentCount, card.currency);

  return CreditCardRevolvingInterestEstimate(
    card: card,
    minimumPaymentEstimate: minimumPaymentEstimate,
    rule: activeRule,
    assumedPaymentAmount: paymentAmount,
    revolvingPrincipal: revolvingPrincipal,
    estimatedDailyInterest: dailyInterest,
    estimatedCycleInterest: cycleInterest,
    minimumPaymentShortfall: minimumShortfall,
    estimatedLateFee: lateFee,
    hasRevolvingPrincipal: revolvingPrincipal > 0,
    hasLateFeeRisk: lateFee > 0,
  );
}

double _lateFeeFor(CreditCardRevolvingInterestRule rule, int missedMinimumPaymentCount, CurrencyCode currency) {
  if (rule.lateFeeTiers.isEmpty || missedMinimumPaymentCount <= 0) return 0;
  var selected = rule.lateFeeTiers.first;
  for (final tier in rule.lateFeeTiers) {
    if (missedMinimumPaymentCount >= tier.missedMinimumPaymentCount) {
      selected = tier;
    }
  }
  return currency.roundAmount(selected.amount);
}
