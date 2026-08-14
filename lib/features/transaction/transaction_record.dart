import '../account/account_record.dart';
import 'transaction_type.dart';

class TransactionRecord {
  const TransactionRecord({
    required this.id,
    required this.type,
    required this.amount,
    required this.category,
    required this.occurredAt,
    required this.accountName,
    required this.memberName,
    required this.merchantName,
    required this.tagName,
    required this.note,
    this.currency = CurrencyCode.twd,
    this.exchangeRateToBase = 1,
    this.fromAccountName,
    this.toAccountName,
    this.repaymentGroupId,
  });

  final String id;
  final TransactionType type;
  final double amount;
  final String category;
  final DateTime occurredAt;
  final String accountName;
  final String memberName;
  final String merchantName;
  final String tagName;
  final String note;
  final CurrencyCode currency;
  final double exchangeRateToBase;
  final String? fromAccountName;
  final String? toAccountName;
  final String? repaymentGroupId;

  bool get isLoanRepayment => repaymentGroupId != null && repaymentGroupId!.trim().isNotEmpty;
  double get roundedAmount => currency.roundAmount(amount);
  double get baseAmount => currency.roundAmount(amount) * exchangeRateToBase;

  TransactionRecord copyWith({
    String? id,
    TransactionType? type,
    double? amount,
    String? category,
    DateTime? occurredAt,
    String? accountName,
    String? memberName,
    String? merchantName,
    String? tagName,
    String? note,
    CurrencyCode? currency,
    double? exchangeRateToBase,
    String? fromAccountName,
    String? toAccountName,
    String? repaymentGroupId,
  }) {
    final nextCurrency = currency ?? this.currency;
    return TransactionRecord(
      id: id ?? this.id,
      type: type ?? this.type,
      amount: nextCurrency.roundAmount(amount ?? this.amount),
      category: category ?? this.category,
      occurredAt: occurredAt ?? this.occurredAt,
      accountName: accountName ?? this.accountName,
      memberName: memberName ?? this.memberName,
      merchantName: merchantName ?? this.merchantName,
      tagName: tagName ?? this.tagName,
      note: note ?? this.note,
      currency: nextCurrency,
      exchangeRateToBase: exchangeRateToBase ?? this.exchangeRateToBase,
      fromAccountName: fromAccountName ?? this.fromAccountName,
      toAccountName: toAccountName ?? this.toAccountName,
      repaymentGroupId: repaymentGroupId ?? this.repaymentGroupId,
    );
  }

  Map<String, Object?> toMap() {
    final storedAmount = currency.roundAmount(amount);
    return {
      'id': id,
      'type': type.name,
      'amount': storedAmount,
      'category': category,
      'occurred_at': occurredAt.toIso8601String(),
      'account_name': accountName,
      'member_name': memberName,
      'merchant_name': merchantName,
      'tag_name': tagName,
      'note': note,
      'currency_code': currency.code,
      'exchange_rate_to_base': exchangeRateToBase,
      'base_amount': storedAmount * exchangeRateToBase,
      'from_account_name': fromAccountName,
      'to_account_name': toAccountName,
      'repayment_group_id': repaymentGroupId,
    };
  }

  factory TransactionRecord.fromMap(Map<String, Object?> map) {
    final currency = currencyFromCode(map['currency_code'] as String?);
    return TransactionRecord(
      id: map['id'] as String,
      type: TransactionType.values.byName(map['type'] as String),
      amount: currency.roundAmount((map['amount'] as num).toDouble()),
      category: map['category'] as String,
      occurredAt: DateTime.parse(map['occurred_at'] as String),
      accountName: map['account_name'] as String,
      memberName: map['member_name'] as String,
      merchantName: map['merchant_name'] as String,
      tagName: map['tag_name'] as String,
      note: map['note'] as String,
      currency: currency,
      exchangeRateToBase: (map['exchange_rate_to_base'] as num?)?.toDouble() ?? 1,
      fromAccountName: map['from_account_name'] as String?,
      toAccountName: map['to_account_name'] as String?,
      repaymentGroupId: map['repayment_group_id'] as String?,
    );
  }
}
