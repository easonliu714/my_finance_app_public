class TransactionModel {
  final int? id;
  final double amount;
  final String type; // income, expense, transfer
  final int accountId;
  final int? toAccountId;
  final int categoryId;
  final DateTime datetime;
  final String? merchant;
  final String? member;
  final bool isReimbursable;
  final String? note;

  TransactionModel({
    this.id,
    required this.amount,
    required this.type,
    required this.accountId,
    this.toAccountId,
    required this.categoryId,
    required this.datetime,
    this.merchant,
    this.member,
    this.isReimbursable = false,
    this.note,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'type': type,
      'account_id': accountId,
      'to_account_id': toAccountId,
      'category_id': categoryId,
      'datetime': datetime.toIso8601String(),
      'merchant': merchant,
      'member': member,
      'is_reimbursable': isReimbursable ? 1 : 0,
      'note': note,
    };
  }
}
