import 'account_record.dart';

class AccountEventRecord {
  const AccountEventRecord({
    required this.id,
    required this.accountId,
    required this.accountName,
    required this.eventType,
    required this.amount,
    required this.currency,
    required this.exchangeRateToBase,
    required this.occurredAt,
    this.note = '',
  });

  final String id;
  final String accountId;
  final String accountName;
  final String eventType;
  final double amount;
  final CurrencyCode currency;
  final double exchangeRateToBase;
  final DateTime occurredAt;
  final String note;

  double get baseAmount => amount * exchangeRateToBase;
  bool get isInitialBalance => eventType == 'initial_balance';
  bool get isBalanceCorrection => eventType == 'balance_correction';

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'account_id': accountId,
      'account_name': accountName,
      'event_type': eventType,
      'amount': amount,
      'currency_code': currency.code,
      'exchange_rate_to_base': exchangeRateToBase,
      'base_amount': baseAmount,
      'occurred_at': occurredAt.toIso8601String(),
      'note': note,
    };
  }

  factory AccountEventRecord.fromMap(Map<String, Object?> map) {
    return AccountEventRecord(
      id: map['id'] as String,
      accountId: map['account_id'] as String,
      accountName: map['account_name'] as String,
      eventType: map['event_type'] as String,
      amount: (map['amount'] as num).toDouble(),
      currency: currencyFromCode(map['currency_code'] as String?),
      exchangeRateToBase: (map['exchange_rate_to_base'] as num?)?.toDouble() ?? 1,
      occurredAt: DateTime.parse(map['occurred_at'] as String),
      note: map['note'] as String? ?? '',
    );
  }
}
