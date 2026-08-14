import 'dart:math' as math;

import '../account/account_record.dart';

enum CreditCardInstallmentScenario {
  purchaseTime('消費當下分期'),
  postStatementSpecifiedAmount('事後指定金額分期');

  const CreditCardInstallmentScenario(this.label);
  final String label;
}

enum CreditCardInstallmentFeeMode {
  totalFee('總費用'),
  annualRate('年利率估算');

  const CreditCardInstallmentFeeMode(this.label);
  final String label;
}

enum CreditCardInstallmentRemainderPolicy {
  firstPeriod('除不盡差額計入第一期'),
  lastPeriod('除不盡差額計入最後一期');

  const CreditCardInstallmentRemainderPolicy(this.label);
  final String label;
}

class CreditCardInstallmentPlanInput {
  const CreditCardInstallmentPlanInput({
    required this.id,
    required this.scenario,
    required this.cardId,
    required this.cardName,
    required this.currency,
    required this.principal,
    required this.termCount,
    required this.firstStatementDate,
    this.sourceTransactionId,
    this.sourceStatementId,
    this.applicationDate,
    this.feeMode = CreditCardInstallmentFeeMode.totalFee,
    this.totalFee = 0,
    this.annualRate = 0,
    this.remainderPolicy = CreditCardInstallmentRemainderPolicy.firstPeriod,
    this.originalUnpaidBalance = 0,
    this.note = '',
  });

  final String id;
  final CreditCardInstallmentScenario scenario;
  final String cardId;
  final String cardName;
  final CurrencyCode currency;
  final double principal;
  final int termCount;
  final DateTime firstStatementDate;
  final String? sourceTransactionId;
  final String? sourceStatementId;
  final DateTime? applicationDate;
  final CreditCardInstallmentFeeMode feeMode;
  final double totalFee;
  final double annualRate;
  final CreditCardInstallmentRemainderPolicy remainderPolicy;
  final double originalUnpaidBalance;
  final String note;

  double get roundedPrincipal => currency.roundAmount(principal);
  double get roundedOriginalUnpaidBalance => currency.roundAmount(originalUnpaidBalance);
  bool get isValid => roundedPrincipal > 0 && termCount > 0;
}

class CreditCardInstallmentScheduleItem {
  const CreditCardInstallmentScheduleItem({
    required this.planId,
    required this.periodNumber,
    required this.statementDate,
    required this.principal,
    required this.fee,
    required this.totalPayment,
    required this.remainingPrincipalAfterPayment,
    required this.revolvingExposureOffset,
    required this.revolvingExposureAfterOffset,
  });

  final String planId;
  final int periodNumber;
  final DateTime statementDate;
  final double principal;
  final double fee;
  final double totalPayment;
  final double remainingPrincipalAfterPayment;
  final double revolvingExposureOffset;
  final double revolvingExposureAfterOffset;
}

class CreditCardInstallmentSchedule {
  const CreditCardInstallmentSchedule({
    required this.input,
    required this.items,
    required this.totalPrincipal,
    required this.totalFee,
    required this.grandTotal,
    required this.immediateRevolvingExposureOffset,
    required this.remainingRevolvingExposureAfterOffset,
  });

  final CreditCardInstallmentPlanInput input;
  final List<CreditCardInstallmentScheduleItem> items;
  final double totalPrincipal;
  final double totalFee;
  final double grandTotal;
  final double immediateRevolvingExposureOffset;
  final double remainingRevolvingExposureAfterOffset;

  bool get isPostStatementSpecifiedAmount => input.scenario == CreditCardInstallmentScenario.postStatementSpecifiedAmount;
}

CreditCardInstallmentSchedule buildCreditCardInstallmentSchedule(CreditCardInstallmentPlanInput input) {
  final currency = input.currency;
  final principalUnits = _toUnits(currency, input.roundedPrincipal);
  if (principalUnits <= 0) {
    throw ArgumentError.value(input.principal, 'principal', 'must be greater than 0');
  }
  if (input.termCount <= 0) {
    throw ArgumentError.value(input.termCount, 'termCount', 'must be greater than 0');
  }

  final feeUnits = _toUnits(currency, _estimateTotalFee(input));
  final principalByPeriod = _splitUnits(principalUnits, input.termCount, input.remainderPolicy);
  final feeByPeriod = _splitUnits(feeUnits, input.termCount, input.remainderPolicy);
  final originalUnpaidBalanceUnits = _nonNegativeUnits(currency, input.roundedOriginalUnpaidBalance);
  final immediateExposureOffsetUnits = _resolveImmediateExposureOffsetUnits(input, principalUnits, originalUnpaidBalanceUnits);
  final remainingExposureAfterOffsetUnits = input.scenario == CreditCardInstallmentScenario.postStatementSpecifiedAmount
      ? math.max(0, originalUnpaidBalanceUnits - immediateExposureOffsetUnits)
      : 0;

  var paidPrincipalUnits = 0;
  final items = <CreditCardInstallmentScheduleItem>[];
  for (var index = 0; index < input.termCount; index++) {
    final periodPrincipalUnits = principalByPeriod[index];
    final periodFeeUnits = feeByPeriod[index];
    paidPrincipalUnits += periodPrincipalUnits;

    items.add(
      CreditCardInstallmentScheduleItem(
        planId: input.id,
        periodNumber: index + 1,
        statementDate: _addMonthsClamped(input.firstStatementDate, index),
        principal: _fromUnits(currency, periodPrincipalUnits),
        fee: _fromUnits(currency, periodFeeUnits),
        totalPayment: _fromUnits(currency, periodPrincipalUnits + periodFeeUnits),
        remainingPrincipalAfterPayment: _fromUnits(currency, math.max(0, principalUnits - paidPrincipalUnits)),
        revolvingExposureOffset: index == 0 ? _fromUnits(currency, immediateExposureOffsetUnits) : 0,
        revolvingExposureAfterOffset: index == 0 ? _fromUnits(currency, remainingExposureAfterOffsetUnits) : 0,
      ),
    );
  }

  return CreditCardInstallmentSchedule(
    input: input,
    items: List.unmodifiable(items),
    totalPrincipal: _fromUnits(currency, principalUnits),
    totalFee: _fromUnits(currency, feeUnits),
    grandTotal: _fromUnits(currency, principalUnits + feeUnits),
    immediateRevolvingExposureOffset: _fromUnits(currency, immediateExposureOffsetUnits),
    remainingRevolvingExposureAfterOffset: _fromUnits(currency, remainingExposureAfterOffsetUnits),
  );
}

double _estimateTotalFee(CreditCardInstallmentPlanInput input) {
  final currency = input.currency;
  final fixedFee = currency.roundAmount(math.max(0.0, input.totalFee));
  final annualRateFee = input.annualRate <= 0 ? 0.0 : currency.roundAmount(input.roundedPrincipal * (input.annualRate / 100) * input.termCount / 12);
  switch (input.feeMode) {
    case CreditCardInstallmentFeeMode.totalFee:
      return currency.roundAmount(fixedFee + annualRateFee);
    case CreditCardInstallmentFeeMode.annualRate:
      return currency.roundAmount(fixedFee + annualRateFee);
  }
}

int _resolveImmediateExposureOffsetUnits(CreditCardInstallmentPlanInput input, int principalUnits, int originalUnpaidBalanceUnits) {
  if (input.scenario != CreditCardInstallmentScenario.postStatementSpecifiedAmount) return 0;
  if (originalUnpaidBalanceUnits <= 0) return principalUnits;
  return math.min(principalUnits, originalUnpaidBalanceUnits);
}

List<int> _splitUnits(int totalUnits, int termCount, CreditCardInstallmentRemainderPolicy policy) {
  final baseUnits = totalUnits ~/ termCount;
  final remainderUnits = totalUnits % termCount;
  final units = List<int>.filled(termCount, baseUnits);
  if (remainderUnits == 0) return units;
  switch (policy) {
    case CreditCardInstallmentRemainderPolicy.firstPeriod:
      units[0] += remainderUnits;
      return units;
    case CreditCardInstallmentRemainderPolicy.lastPeriod:
      units[termCount - 1] += remainderUnits;
      return units;
  }
}

int _nonNegativeUnits(CurrencyCode currency, double amount) {
  final units = _toUnits(currency, amount);
  return units < 0 ? 0 : units;
}

int _toUnits(CurrencyCode currency, double amount) {
  return (currency.roundAmount(amount) * currency.roundingScale).round();
}

double _fromUnits(CurrencyCode currency, int units) {
  return currency.roundAmount(units / currency.roundingScale);
}

DateTime _addMonthsClamped(DateTime source, int monthOffset) {
  final monthIndex = source.month - 1 + monthOffset;
  final targetYear = source.year + monthIndex ~/ 12;
  final targetMonth = monthIndex % 12 + 1;
  final targetDay = math.min(source.day, _daysInMonth(targetYear, targetMonth));
  return DateTime(
    targetYear,
    targetMonth,
    targetDay,
    source.hour,
    source.minute,
    source.second,
    source.millisecond,
    source.microsecond,
  );
}

int _daysInMonth(int year, int month) {
  final firstDayOfNextMonth = month == 12 ? DateTime(year + 1) : DateTime(year, month + 1);
  return firstDayOfNextMonth.subtract(const Duration(days: 1)).day;
}
