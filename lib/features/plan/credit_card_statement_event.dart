import '../account/account_record.dart';

class CreditCardStatementEvent {
  const CreditCardStatementEvent({
    required this.id,
    required this.cardId,
    required this.cardName,
    required this.currency,
    required this.statementDate,
    required this.dueDate,
    required this.periodStart,
    required this.periodEnd,
    required this.totalBalance,
    required this.minimumPayment,
    required this.paidAmount,
    required this.unpaidBalance,
    required this.estimatedRevolvingInterest,
    required this.estimatedLateFee,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String cardId;
  final String cardName;
  final CurrencyCode currency;
  final DateTime statementDate;
  final DateTime dueDate;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double totalBalance;
  final double minimumPayment;
  final double paidAmount;
  final double unpaidBalance;
  final double estimatedRevolvingInterest;
  final double estimatedLateFee;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isFullyPaid => unpaidBalance <= 0;
  bool get isBelowMinimum => paidAmount < minimumPayment && unpaidBalance > 0;

  CreditCardStatementEvent copyWith({
    String? id,
    String? cardId,
    String? cardName,
    CurrencyCode? currency,
    DateTime? statementDate,
    DateTime? dueDate,
    DateTime? periodStart,
    DateTime? periodEnd,
    double? totalBalance,
    double? minimumPayment,
    double? paidAmount,
    double? unpaidBalance,
    double? estimatedRevolvingInterest,
    double? estimatedLateFee,
    String? note,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CreditCardStatementEvent(
      id: id ?? this.id,
      cardId: cardId ?? this.cardId,
      cardName: cardName ?? this.cardName,
      currency: currency ?? this.currency,
      statementDate: statementDate ?? this.statementDate,
      dueDate: dueDate ?? this.dueDate,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      totalBalance: totalBalance ?? this.totalBalance,
      minimumPayment: minimumPayment ?? this.minimumPayment,
      paidAmount: paidAmount ?? this.paidAmount,
      unpaidBalance: unpaidBalance ?? this.unpaidBalance,
      estimatedRevolvingInterest: estimatedRevolvingInterest ?? this.estimatedRevolvingInterest,
      estimatedLateFee: estimatedLateFee ?? this.estimatedLateFee,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    final roundedTotal = currency.roundAmount(totalBalance);
    final roundedMinimum = currency.roundAmount(minimumPayment);
    final roundedPaid = currency.roundAmount(paidAmount);
    final roundedUnpaid = currency.roundAmount(unpaidBalance);
    final roundedInterest = currency.roundAmount(estimatedRevolvingInterest);
    final roundedLateFee = currency.roundAmount(estimatedLateFee);
    return {
      'id': id,
      'card_id': cardId,
      'card_name': cardName,
      'currency_code': currency.code,
      'statement_date': statementDate.toIso8601String(),
      'due_date': dueDate.toIso8601String(),
      'period_start': periodStart.toIso8601String(),
      'period_end': periodEnd.toIso8601String(),
      'total_balance': roundedTotal,
      'minimum_payment': roundedMinimum,
      'paid_amount': roundedPaid,
      'unpaid_balance': roundedUnpaid,
      'estimated_revolving_interest': roundedInterest,
      'estimated_late_fee': roundedLateFee,
      'note': note,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory CreditCardStatementEvent.fromMap(Map<String, Object?> map) {
    final currency = currencyFromCode(map['currency_code'] as String?);
    return CreditCardStatementEvent(
      id: map['id'] as String,
      cardId: map['card_id'] as String,
      cardName: map['card_name'] as String,
      currency: currency,
      statementDate: DateTime.parse(map['statement_date'] as String),
      dueDate: DateTime.parse(map['due_date'] as String),
      periodStart: DateTime.parse(map['period_start'] as String),
      periodEnd: DateTime.parse(map['period_end'] as String),
      totalBalance: currency.roundAmount((map['total_balance'] as num).toDouble()),
      minimumPayment: currency.roundAmount((map['minimum_payment'] as num).toDouble()),
      paidAmount: currency.roundAmount((map['paid_amount'] as num).toDouble()),
      unpaidBalance: currency.roundAmount((map['unpaid_balance'] as num).toDouble()),
      estimatedRevolvingInterest: currency.roundAmount((map['estimated_revolving_interest'] as num?)?.toDouble() ?? 0.0),
      estimatedLateFee: currency.roundAmount((map['estimated_late_fee'] as num?)?.toDouble() ?? 0.0),
      note: map['note'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
