enum TransactionType {
  income,
  expense,
  transfer,
  loan;

  String get label {
    switch (this) {
      case TransactionType.income:
        return '收入';
      case TransactionType.expense:
        return '支出';
      case TransactionType.transfer:
        return '轉帳';
      case TransactionType.loan:
        return '借貸';
    }
  }
}
