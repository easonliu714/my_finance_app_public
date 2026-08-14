import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_repository.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_service.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_source.dart';

void main() {
  group('InstallmentPlanSourceExtension', () {
    test('infers purchase transaction source from sourceTransactionId', () {
      final plan = _plan(sourceTransactionId: 'tx-1');

      expect(plan.inferredSourceType, InstallmentSourceType.purchaseTransaction);
      expect(plan.inferredSourceType.code, 'purchase_transaction');
      expect(plan.inferredExpenseRecognitionMode, InstallmentExpenseRecognitionMode.immediate);
      expect(plan.inferredPrincipalAccountingMode, InstallmentPrincipalAccountingMode.deferCardCharge);
      expect(plan.requiresSourceTransactionGuard, isTrue);
      expect(plan.requiresSourceStatementGuard, isFalse);
      expect(plan.requiresFinancingAccount, isFalse);
    });

    test('infers statement balance source from post statement scenario', () {
      final plan = _plan(
        scenario: CreditCardInstallmentScenario.postStatementSpecifiedAmount,
        sourceStatementId: 'statement-1',
      );

      expect(plan.inferredSourceType, InstallmentSourceType.statementBalance);
      expect(plan.inferredSourceType.code, 'statement_balance');
      expect(plan.inferredExpenseRecognitionMode, InstallmentExpenseRecognitionMode.perPeriod);
      expect(plan.inferredPrincipalAccountingMode, InstallmentPrincipalAccountingMode.offsetStatementBalance);
      expect(plan.requiresSourceTransactionGuard, isFalse);
      expect(plan.requiresSourceStatementGuard, isTrue);
      expect(plan.requiresFinancingAccount, isFalse);
    });

    test('infers manual BNPL source when no transaction or statement source exists', () {
      final plan = _plan();

      expect(plan.inferredSourceType, InstallmentSourceType.manualBnpl);
      expect(plan.inferredSourceType.code, 'manual_bnpl');
      expect(plan.inferredExpenseRecognitionMode, InstallmentExpenseRecognitionMode.immediate);
      expect(plan.inferredPrincipalAccountingMode, InstallmentPrincipalAccountingMode.financeLiability);
      expect(plan.requiresSourceTransactionGuard, isFalse);
      expect(plan.requiresSourceStatementGuard, isFalse);
      expect(plan.requiresFinancingAccount, isTrue);
    });
  });
}

InstallmentPlanRecord _plan({
  CreditCardInstallmentScenario scenario = CreditCardInstallmentScenario.purchaseTime,
  String? sourceTransactionId,
  String? sourceStatementId,
}) {
  return InstallmentPlanRecord(
    id: 'plan-1',
    scenario: scenario,
    cardId: 'card-1',
    cardNameSnapshot: 'Test Card',
    currency: CurrencyCode.twd,
    principal: 12000,
    termCount: 6,
    firstStatementDate: DateTime(2026, 7, 5),
    feeMode: CreditCardInstallmentFeeMode.totalFee,
    totalFee: 0,
    annualRate: 0,
    remainderPolicy: CreditCardInstallmentRemainderPolicy.firstPeriod,
    originalUnpaidBalance: 0,
    sourceTransactionId: sourceTransactionId,
    sourceStatementId: sourceStatementId,
    status: InstallmentPlanStatus.active,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}
