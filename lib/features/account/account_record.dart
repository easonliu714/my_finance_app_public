enum AccountType {
  cash('現金'),
  bank('銀行'),
  debitCard('簽帳金融卡'),
  creditCard('信用卡'),
  storedValue('儲值卡'),
  eWallet('電子錢包'),
  investment('投資'),
  loan('借貸'),
  other('其他');

  const AccountType(this.label);
  final String label;
}

enum CurrencyCode {
  twd('TWD', '新台幣', 1),
  usd('USD', '美元', 31.55),
  jpy('JPY', '日圓', 0.21),
  cny('CNY', '人民幣', 4.35),
  hkd('HKD', '港幣', 4.04),
  eur('EUR', '歐元', 34.20),
  gbp('GBP', '英鎊', 39.80),
  krw('KRW', '韓元', 0.023),
  sgd('SGD', '新加坡幣', 23.60),
  aud('AUD', '澳幣', 20.70),
  cad('CAD', '加拿大幣', 23.10),
  thb('THB', '泰銖', 0.86);

  const CurrencyCode(this.code, this.label, this.defaultRateToTwd);
  final String code;
  final String label;
  final double defaultRateToTwd;

  String get displayLabel => '$code $label';

  int get decimalDigits {
    switch (this) {
      case CurrencyCode.twd:
      case CurrencyCode.jpy:
      case CurrencyCode.krw:
        return 0;
      case CurrencyCode.usd:
      case CurrencyCode.cny:
      case CurrencyCode.hkd:
      case CurrencyCode.eur:
      case CurrencyCode.gbp:
      case CurrencyCode.sgd:
      case CurrencyCode.aud:
      case CurrencyCode.cad:
      case CurrencyCode.thb:
        return 2;
    }
  }

  double get roundingScale => decimalDigits == 0 ? 1 : 100;

  double roundAmount(double value) =>
      (value * roundingScale).roundToDouble() / roundingScale;
}

enum LoanRepaymentMethod {
  principalOnly('等額還本附息（總利息最低）'),
  interestOnly('等額還息期末還本（總利息最高）'),
  equalPrincipalAndInterest('等額本息還款');

  const LoanRepaymentMethod(this.label);
  final String label;
}

LoanRepaymentMethod loanRepaymentMethodFromName(String? name) {
  if (name == null || name.trim().isEmpty) {
    return LoanRepaymentMethod.equalPrincipalAndInterest;
  }
  return LoanRepaymentMethod.values.firstWhere(
    (item) => item.name == name,
    orElse: () => LoanRepaymentMethod.equalPrincipalAndInterest,
  );
}

CurrencyCode currencyFromCode(String? code) {
  if (code == null || code.trim().isEmpty) return CurrencyCode.twd;
  return CurrencyCode.values.firstWhere(
    (item) => item.code == code || item.name == code,
    orElse: () => CurrencyCode.twd,
  );
}

class AccountRecord {
  const AccountRecord({
    required this.id,
    required this.name,
    required this.type,
    required this.initialBalance,
    required this.sortOrder,
    this.suffix = '',
    this.currency = CurrencyCode.twd,
    this.creditLimit = 0,
    this.statementDay = 1,
    this.paymentDueDay = 1,
    this.paymentReminderEnabled = false,
    this.reminderDaysBefore = 3,
    this.loanPrincipal = 0,
    this.annualInterestRate = 0,
    this.loanTermMonths = 0,
    this.loanRepaymentMethod = LoanRepaymentMethod.equalPrincipalAndInterest,
    this.loanPaymentDueDay = 1,
    this.loanReminderEnabled = false,
    this.loanReminderDaysBefore = 3,
    this.loanStartDate,
    this.loanDisbursementAccountName = '',
    this.loanHandlingFee = 0,
    this.loanDisbursementCreated = false,
    this.note = '',
    this.isArchived = false,
  });

  final String id;
  final String name;
  final AccountType type;
  final double initialBalance;
  final int sortOrder;
  final String suffix;
  final CurrencyCode currency;
  final double creditLimit;
  final int statementDay;
  final int paymentDueDay;
  final bool paymentReminderEnabled;
  final int reminderDaysBefore;
  final double loanPrincipal;
  final double annualInterestRate;
  final int loanTermMonths;
  final LoanRepaymentMethod loanRepaymentMethod;
  final int loanPaymentDueDay;
  final bool loanReminderEnabled;
  final int loanReminderDaysBefore;
  final DateTime? loanStartDate;
  final String loanDisbursementAccountName;
  final double loanHandlingFee;
  final bool loanDisbursementCreated;
  final String note;
  final bool isArchived;

  String get displayName =>
      suffix.trim().isEmpty ? name : '$name・$suffix';
  bool get isCreditCard => type == AccountType.creditCard;
  bool get isDebitCard => type == AccountType.debitCard;
  bool get isLoan => type == AccountType.loan;
  double get availableCreditByInitialBalance =>
      creditLimit <= 0 ? 0 : creditLimit - initialBalance.abs();
  double get loanNetDisbursement =>
      currency.roundAmount(loanPrincipal - loanHandlingFee);

  double get monthlyInterestRate =>
      annualInterestRate <= 0 ? 0 : annualInterestRate / 100 / 12;

  double get estimatedMonthlyPayment =>
      _roundLoanAmount(_estimatedMonthlyPaymentRaw);

  double get _estimatedMonthlyPaymentRaw {
    if (!isLoan || loanPrincipal <= 0 || loanTermMonths <= 0) return 0;
    final r = monthlyInterestRate;
    switch (loanRepaymentMethod) {
      case LoanRepaymentMethod.principalOnly:
        return loanPrincipal / loanTermMonths;
      case LoanRepaymentMethod.interestOnly:
        return loanPrincipal * r;
      case LoanRepaymentMethod.equalPrincipalAndInterest:
        if (r == 0) return loanPrincipal / loanTermMonths;
        final factor = _pow(1 + r, loanTermMonths);
        return loanPrincipal * r * factor / (factor - 1);
    }
  }

  double get estimatedFirstMonthInterest {
    if (!isLoan || loanPrincipal <= 0) return 0;
    return _roundLoanAmount(loanPrincipal * monthlyInterestRate);
  }

  double get estimatedFirstMonthPrincipal {
    if (!isLoan || loanPrincipal <= 0 || loanTermMonths <= 0) return 0;
    switch (loanRepaymentMethod) {
      case LoanRepaymentMethod.principalOnly:
        return _roundLoanAmount(loanPrincipal / loanTermMonths);
      case LoanRepaymentMethod.interestOnly:
        return 0;
      case LoanRepaymentMethod.equalPrincipalAndInterest:
        return _roundLoanAmount(
          _estimatedMonthlyPaymentRaw - estimatedFirstMonthInterest,
        );
    }
  }

  double _roundLoanAmount(double value) => currency.roundAmount(value);

  AccountRecord copyWith({
    String? id,
    String? name,
    AccountType? type,
    double? initialBalance,
    int? sortOrder,
    String? suffix,
    CurrencyCode? currency,
    double? creditLimit,
    int? statementDay,
    int? paymentDueDay,
    bool? paymentReminderEnabled,
    int? reminderDaysBefore,
    double? loanPrincipal,
    double? annualInterestRate,
    int? loanTermMonths,
    LoanRepaymentMethod? loanRepaymentMethod,
    int? loanPaymentDueDay,
    bool? loanReminderEnabled,
    int? loanReminderDaysBefore,
    DateTime? loanStartDate,
    String? loanDisbursementAccountName,
    double? loanHandlingFee,
    bool? loanDisbursementCreated,
    String? note,
    bool? isArchived,
  }) {
    return AccountRecord(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      initialBalance: initialBalance ?? this.initialBalance,
      sortOrder: sortOrder ?? this.sortOrder,
      suffix: suffix ?? this.suffix,
      currency: currency ?? this.currency,
      creditLimit: creditLimit ?? this.creditLimit,
      statementDay: statementDay ?? this.statementDay,
      paymentDueDay: paymentDueDay ?? this.paymentDueDay,
      paymentReminderEnabled:
          paymentReminderEnabled ?? this.paymentReminderEnabled,
      reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
      loanPrincipal: loanPrincipal ?? this.loanPrincipal,
      annualInterestRate: annualInterestRate ?? this.annualInterestRate,
      loanTermMonths: loanTermMonths ?? this.loanTermMonths,
      loanRepaymentMethod:
          loanRepaymentMethod ?? this.loanRepaymentMethod,
      loanPaymentDueDay: loanPaymentDueDay ?? this.loanPaymentDueDay,
      loanReminderEnabled: loanReminderEnabled ?? this.loanReminderEnabled,
      loanReminderDaysBefore:
          loanReminderDaysBefore ?? this.loanReminderDaysBefore,
      loanStartDate: loanStartDate ?? this.loanStartDate,
      loanDisbursementAccountName:
          loanDisbursementAccountName ?? this.loanDisbursementAccountName,
      loanHandlingFee: loanHandlingFee ?? this.loanHandlingFee,
      loanDisbursementCreated:
          loanDisbursementCreated ?? this.loanDisbursementCreated,
      note: note ?? this.note,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'initial_balance': initialBalance,
      'sort_order': sortOrder,
      'suffix': suffix,
      'currency_code': currency.code,
      'credit_limit': creditLimit,
      'statement_day': statementDay,
      'payment_due_day': paymentDueDay,
      'payment_reminder_enabled': paymentReminderEnabled ? 1 : 0,
      'reminder_days_before': reminderDaysBefore,
      'loan_principal': loanPrincipal,
      'annual_interest_rate': annualInterestRate,
      'loan_term_months': loanTermMonths,
      'loan_repayment_method': loanRepaymentMethod.name,
      'loan_payment_due_day': loanPaymentDueDay,
      'loan_reminder_enabled': loanReminderEnabled ? 1 : 0,
      'loan_reminder_days_before': loanReminderDaysBefore,
      'loan_start_date': loanStartDate?.toIso8601String(),
      'loan_disbursement_account_name': loanDisbursementAccountName,
      'loan_handling_fee': loanHandlingFee,
      'loan_disbursement_created': loanDisbursementCreated ? 1 : 0,
      'note': note,
      'is_archived': isArchived ? 1 : 0,
    };
  }

  factory AccountRecord.fromMap(Map<String, Object?> map) {
    final loanStartText = map['loan_start_date'] as String?;
    return AccountRecord(
      id: map['id'] as String,
      name: map['name'] as String,
      type: AccountType.values.byName(map['type'] as String),
      initialBalance: (map['initial_balance'] as num).toDouble(),
      sortOrder: (map['sort_order'] as num).toInt(),
      suffix: map['suffix'] as String? ?? '',
      currency: currencyFromCode(map['currency_code'] as String?),
      creditLimit: (map['credit_limit'] as num?)?.toDouble() ?? 0,
      statementDay: (map['statement_day'] as num?)?.toInt() ?? 1,
      paymentDueDay: (map['payment_due_day'] as num?)?.toInt() ?? 1,
      paymentReminderEnabled:
          (map['payment_reminder_enabled'] as num?)?.toInt() == 1,
      reminderDaysBefore:
          (map['reminder_days_before'] as num?)?.toInt() ?? 3,
      loanPrincipal: (map['loan_principal'] as num?)?.toDouble() ?? 0,
      annualInterestRate:
          (map['annual_interest_rate'] as num?)?.toDouble() ?? 0,
      loanTermMonths: (map['loan_term_months'] as num?)?.toInt() ?? 0,
      loanRepaymentMethod: loanRepaymentMethodFromName(
        map['loan_repayment_method'] as String?,
      ),
      loanPaymentDueDay:
          (map['loan_payment_due_day'] as num?)?.toInt() ?? 1,
      loanReminderEnabled:
          (map['loan_reminder_enabled'] as num?)?.toInt() == 1,
      loanReminderDaysBefore:
          (map['loan_reminder_days_before'] as num?)?.toInt() ?? 3,
      loanStartDate: loanStartText == null || loanStartText.trim().isEmpty
          ? null
          : DateTime.tryParse(loanStartText),
      loanDisbursementAccountName:
          map['loan_disbursement_account_name'] as String? ?? '',
      loanHandlingFee:
          (map['loan_handling_fee'] as num?)?.toDouble() ?? 0,
      loanDisbursementCreated:
          (map['loan_disbursement_created'] as num?)?.toInt() == 1,
      note: map['note'] as String? ?? '',
      isArchived: (map['is_archived'] as num?)?.toInt() == 1,
    );
  }
}

double _pow(double base, int exponent) {
  var result = 1.0;
  for (var i = 0; i < exponent; i++) {
    result *= base;
  }
  return result;
}
