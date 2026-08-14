import 'credit_card_installment_repository.dart';
import 'credit_card_installment_service.dart';

enum InstallmentSourceType {
  purchaseTransaction,
  statementBalance,
  manualBnpl,
}

enum InstallmentExpenseRecognitionMode {
  immediate,
  perPeriod,
}

enum InstallmentPrincipalAccountingMode {
  deferCardCharge,
  offsetStatementBalance,
  financeLiability,
}

extension InstallmentSourceTypeLabel on InstallmentSourceType {
  String get code => switch (this) {
        InstallmentSourceType.purchaseTransaction => 'purchase_transaction',
        InstallmentSourceType.statementBalance => 'statement_balance',
        InstallmentSourceType.manualBnpl => 'manual_bnpl',
      };

  String get label => switch (this) {
        InstallmentSourceType.purchaseTransaction => '信用卡當下消費分期',
        InstallmentSourceType.statementBalance => '信用卡事後指定金額分期',
        InstallmentSourceType.manualBnpl => '無卡分期 / BNPL',
      };
}

extension InstallmentExpenseRecognitionModeLabel on InstallmentExpenseRecognitionMode {
  String get code => switch (this) {
        InstallmentExpenseRecognitionMode.immediate => 'immediate',
        InstallmentExpenseRecognitionMode.perPeriod => 'per_period',
      };
}

extension InstallmentPrincipalAccountingModeLabel on InstallmentPrincipalAccountingMode {
  String get code => switch (this) {
        InstallmentPrincipalAccountingMode.deferCardCharge => 'defer_card_charge',
        InstallmentPrincipalAccountingMode.offsetStatementBalance => 'offset_statement_balance',
        InstallmentPrincipalAccountingMode.financeLiability => 'finance_liability',
      };
}

extension InstallmentPlanSourceExtension on InstallmentPlanRecord {
  InstallmentSourceType get inferredSourceType {
    if (scenario == CreditCardInstallmentScenario.postStatementSpecifiedAmount || _hasValue(sourceStatementId)) {
      return InstallmentSourceType.statementBalance;
    }
    if (_hasValue(sourceTransactionId)) {
      return InstallmentSourceType.purchaseTransaction;
    }
    return InstallmentSourceType.manualBnpl;
  }

  InstallmentExpenseRecognitionMode get inferredExpenseRecognitionMode {
    return switch (inferredSourceType) {
      InstallmentSourceType.purchaseTransaction => InstallmentExpenseRecognitionMode.immediate,
      InstallmentSourceType.statementBalance => InstallmentExpenseRecognitionMode.perPeriod,
      InstallmentSourceType.manualBnpl => InstallmentExpenseRecognitionMode.immediate,
    };
  }

  InstallmentPrincipalAccountingMode get inferredPrincipalAccountingMode {
    return switch (inferredSourceType) {
      InstallmentSourceType.purchaseTransaction => InstallmentPrincipalAccountingMode.deferCardCharge,
      InstallmentSourceType.statementBalance => InstallmentPrincipalAccountingMode.offsetStatementBalance,
      InstallmentSourceType.manualBnpl => InstallmentPrincipalAccountingMode.financeLiability,
    };
  }

  bool get requiresSourceTransactionGuard => inferredSourceType == InstallmentSourceType.purchaseTransaction;

  bool get requiresSourceStatementGuard => inferredSourceType == InstallmentSourceType.statementBalance;

  bool get requiresFinancingAccount => inferredSourceType == InstallmentSourceType.manualBnpl;
}

bool _hasValue(String? value) => value != null && value.trim().isNotEmpty;
