import '../account/account_record.dart';
import 'credit_card_minimum_payment_service.dart';
import 'credit_card_revolving_interest_service.dart';

class CreditCardBankRuleProfile {
  const CreditCardBankRuleProfile({
    required this.id,
    required this.name,
    required this.currency,
    required this.minimumPaymentRate,
    required this.revolvingBalanceRate,
    required this.minimumPaymentFloor,
    required this.cashAdvanceMinimum,
    required this.feeMinimum,
    required this.includeEstimatedFees,
    required this.annualInterestRate,
    required this.daysInYear,
    required this.estimatedCycleDays,
    required this.lateFeeTiers,
    required this.lateFeeWaiveThreshold,
    required this.note,
    required this.isVerifiedAgainstStatement,
  });

  factory CreditCardBankRuleProfile.defaultEstimate(CurrencyCode currency) {
    final minimumRule = CreditCardMinimumPaymentRule.defaultEstimate(currency);
    final revolvingRule = CreditCardRevolvingInterestRule.defaultEstimate(currency);
    return CreditCardBankRuleProfile(
      id: 'default-estimate-${currency.code.toLowerCase()}',
      name: '預設估算規則',
      currency: currency,
      minimumPaymentRate: minimumRule.currentPurchaseRate,
      revolvingBalanceRate: minimumRule.revolvingBalanceRate,
      minimumPaymentFloor: minimumRule.minimumFloor,
      cashAdvanceMinimum: minimumRule.cashAdvanceMinimum,
      feeMinimum: minimumRule.feeMinimum,
      includeEstimatedFees: minimumRule.includeEstimatedFees,
      annualInterestRate: revolvingRule.annualInterestRate,
      daysInYear: revolvingRule.daysInYear,
      estimatedCycleDays: revolvingRule.estimatedCycleDays,
      lateFeeTiers: revolvingRule.lateFeeTiers,
      lateFeeWaiveThreshold: revolvingRule.lateFeeWaiveThreshold,
      note: '系統估算用預設值，尚未對應任何特定銀行條款。實際金額請以銀行帳單與帳單快照校正為準。',
      isVerifiedAgainstStatement: false,
    );
  }

  final String id;
  final String name;
  final CurrencyCode currency;
  final double minimumPaymentRate;
  final double revolvingBalanceRate;
  final double minimumPaymentFloor;
  final double cashAdvanceMinimum;
  final double feeMinimum;
  final bool includeEstimatedFees;
  final double annualInterestRate;
  final int daysInYear;
  final int estimatedCycleDays;
  final List<CreditCardLateFeeTier> lateFeeTiers;
  final double lateFeeWaiveThreshold;
  final String note;
  final bool isVerifiedAgainstStatement;

  CreditCardBankRuleProfile copyWith({
    String? id,
    String? name,
    CurrencyCode? currency,
    double? minimumPaymentRate,
    double? revolvingBalanceRate,
    double? minimumPaymentFloor,
    double? cashAdvanceMinimum,
    double? feeMinimum,
    bool? includeEstimatedFees,
    double? annualInterestRate,
    int? daysInYear,
    int? estimatedCycleDays,
    List<CreditCardLateFeeTier>? lateFeeTiers,
    double? lateFeeWaiveThreshold,
    String? note,
    bool? isVerifiedAgainstStatement,
  }) {
    return CreditCardBankRuleProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      currency: currency ?? this.currency,
      minimumPaymentRate: minimumPaymentRate ?? this.minimumPaymentRate,
      revolvingBalanceRate: revolvingBalanceRate ?? this.revolvingBalanceRate,
      minimumPaymentFloor: minimumPaymentFloor ?? this.minimumPaymentFloor,
      cashAdvanceMinimum: cashAdvanceMinimum ?? this.cashAdvanceMinimum,
      feeMinimum: feeMinimum ?? this.feeMinimum,
      includeEstimatedFees: includeEstimatedFees ?? this.includeEstimatedFees,
      annualInterestRate: annualInterestRate ?? this.annualInterestRate,
      daysInYear: daysInYear ?? this.daysInYear,
      estimatedCycleDays: estimatedCycleDays ?? this.estimatedCycleDays,
      lateFeeTiers: lateFeeTiers ?? this.lateFeeTiers,
      lateFeeWaiveThreshold: lateFeeWaiveThreshold ?? this.lateFeeWaiveThreshold,
      note: note ?? this.note,
      isVerifiedAgainstStatement: isVerifiedAgainstStatement ?? this.isVerifiedAgainstStatement,
    );
  }

  CreditCardMinimumPaymentRule toMinimumPaymentRule() {
    return CreditCardMinimumPaymentRule(
      name: name,
      revolvingBalanceRate: revolvingBalanceRate,
      currentPurchaseRate: minimumPaymentRate,
      minimumFloor: minimumPaymentFloor,
      cashAdvanceMinimum: cashAdvanceMinimum,
      feeMinimum: feeMinimum,
      includeEstimatedFees: includeEstimatedFees,
      disclaimer: note,
    );
  }

  CreditCardRevolvingInterestRule toRevolvingInterestRule() {
    return CreditCardRevolvingInterestRule(
      name: name,
      annualInterestRate: annualInterestRate,
      daysInYear: daysInYear,
      estimatedCycleDays: estimatedCycleDays,
      lateFeeTiers: lateFeeTiers,
      lateFeeWaiveThreshold: lateFeeWaiveThreshold,
      disclaimer: note,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'currency_code': currency.code,
      'minimum_payment_rate': minimumPaymentRate,
      'revolving_balance_rate': revolvingBalanceRate,
      'minimum_payment_floor': minimumPaymentFloor,
      'cash_advance_minimum': cashAdvanceMinimum,
      'fee_minimum': feeMinimum,
      'include_estimated_fees': includeEstimatedFees ? 1 : 0,
      'annual_interest_rate': annualInterestRate,
      'days_in_year': daysInYear,
      'estimated_cycle_days': estimatedCycleDays,
      'late_fee_tiers': _encodeLateFeeTiers(lateFeeTiers),
      'late_fee_waive_threshold': lateFeeWaiveThreshold,
      'note': note,
      'is_verified_against_statement': isVerifiedAgainstStatement ? 1 : 0,
    };
  }

  factory CreditCardBankRuleProfile.fromMap(Map<String, Object?> map) {
    return CreditCardBankRuleProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      currency: currencyFromCode(map['currency_code'] as String?),
      minimumPaymentRate: (map['minimum_payment_rate'] as num).toDouble(),
      revolvingBalanceRate: (map['revolving_balance_rate'] as num).toDouble(),
      minimumPaymentFloor: (map['minimum_payment_floor'] as num).toDouble(),
      cashAdvanceMinimum: (map['cash_advance_minimum'] as num).toDouble(),
      feeMinimum: (map['fee_minimum'] as num).toDouble(),
      includeEstimatedFees: (map['include_estimated_fees'] as num?)?.toInt() != 0,
      annualInterestRate: (map['annual_interest_rate'] as num).toDouble(),
      daysInYear: (map['days_in_year'] as num).toInt(),
      estimatedCycleDays: (map['estimated_cycle_days'] as num).toInt(),
      lateFeeTiers: _decodeLateFeeTiers(map['late_fee_tiers'] as String? ?? ''),
      lateFeeWaiveThreshold: (map['late_fee_waive_threshold'] as num).toDouble(),
      note: map['note'] as String? ?? '',
      isVerifiedAgainstStatement: (map['is_verified_against_statement'] as num?)?.toInt() == 1,
    );
  }
}

String encodeCreditCardLateFeeTiers(List<CreditCardLateFeeTier> tiers) => _encodeLateFeeTiers(tiers);
List<CreditCardLateFeeTier> decodeCreditCardLateFeeTiers(String value) => _decodeLateFeeTiers(value);

String _encodeLateFeeTiers(List<CreditCardLateFeeTier> tiers) {
  return tiers.map((tier) => '${tier.missedMinimumPaymentCount}:${tier.amount}').join(',');
}

List<CreditCardLateFeeTier> _decodeLateFeeTiers(String value) {
  if (value.trim().isEmpty) return const [];
  final tiers = <CreditCardLateFeeTier>[];
  for (final rawPart in value.split(',')) {
    final part = rawPart.trim();
    if (part.isEmpty) continue;
    final tokens = part.split(':');
    if (tokens.length != 2) continue;
    final count = int.tryParse(tokens[0].trim());
    final amount = double.tryParse(tokens[1].trim());
    if (count == null || amount == null) continue;
    tiers.add(CreditCardLateFeeTier(missedMinimumPaymentCount: count, amount: amount));
  }
  return tiers;
}
