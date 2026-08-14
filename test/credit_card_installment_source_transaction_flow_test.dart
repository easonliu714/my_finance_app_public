import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_repository.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_service.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_source.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_source_transaction_flow.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  group('source transaction installment flow', () {
    test('builds purchase-time installment input from credit card expense transaction', () {
      final input = buildSourceTransactionInstallmentInput(
        id: 'plan-tx-1',
        transaction: _expenseTransaction(),
        card: _creditCard(),
        termCount: 6,
        firstStatementDate: DateTime(2026, 8, 5),
        totalFee: 120,
      );

      expect(input.id, 'plan-tx-1');
      expect(input.scenario, CreditCardInstallmentScenario.purchaseTime);
      expect(input.sourceTransactionId, 'tx-1');
      expect(input.sourceStatementId, isNull);
      expect(input.cardId, 'card-1');
      expect(input.cardName, 'Test Credit Card');
      expect(input.principal, 12000);
      expect(input.termCount, 6);
      expect(input.totalFee, 120);
    });

    test('creates active plan and schedule without side-effect transaction identifiers', () async {
      final repository = InMemoryCreditCardInstallmentRepository();

      final plan = await createInstallmentPlanFromSourceTransaction(
        id: 'plan-tx-1',
        repository: repository,
        transaction: _expenseTransaction(),
        card: _creditCard(),
        termCount: 6,
        firstStatementDate: DateTime(2026, 8, 5),
      );
      final items = await repository.loadScheduleItems(plan.id);

      expect(plan.status, InstallmentPlanStatus.active);
      expect(plan.sourceTransactionId, 'tx-1');
      expect(plan.sourceStatementId, isNull);
      expect(plan.principal, 12000);
      expect(plan.inferredSourceType, InstallmentSourceType.purchaseTransaction);
      expect(plan.inferredPrincipalAccountingMode, InstallmentPrincipalAccountingMode.deferCardCharge);
      expect(items, hasLength(6));
      expect(items.every((item) => item.generatedTransactionId == null), isTrue);
      expect(items.every((item) => item.status == InstallmentScheduleItemStatus.pending), isTrue);
    });

    test('rejects duplicate active source transaction installment plan', () async {
      final repository = InMemoryCreditCardInstallmentRepository();
      await createInstallmentPlanFromSourceTransaction(
        id: 'plan-tx-1',
        repository: repository,
        transaction: _expenseTransaction(),
        card: _creditCard(),
        termCount: 6,
        firstStatementDate: DateTime(2026, 8, 5),
      );

      await expectLater(
        createInstallmentPlanFromSourceTransaction(
          id: 'plan-tx-duplicate',
          repository: repository,
          transaction: _expenseTransaction(),
          card: _creditCard(),
          termCount: 6,
          firstStatementDate: DateTime(2026, 8, 5),
        ),
        throwsA(isA<DuplicateInstallmentSourceFailure>()),
      );
    });

    test('rejects non-credit-card source account', () {
      final eligibility = checkSourceTransactionInstallmentEligibility(
        transaction: _expenseTransaction(),
        card: _cashAccount(),
      );

      expect(eligibility.isEligible, isFalse);
      expect(eligibility.message, contains('信用卡帳戶'));
    });

    test('rejects non-expense transaction', () {
      final eligibility = checkSourceTransactionInstallmentEligibility(
        transaction: _expenseTransaction(type: TransactionType.income),
        card: _creditCard(),
      );

      expect(eligibility.isEligible, isFalse);
      expect(eligibility.message, contains('支出交易'));
    });

    test('rejects mismatched credit card account', () {
      final eligibility = checkSourceTransactionInstallmentEligibility(
        transaction: _expenseTransaction(accountName: 'Other Card'),
        card: _creditCard(),
      );

      expect(eligibility.isEligible, isFalse);
      expect(eligibility.message, contains('不一致'));
    });
  });
}

AccountRecord _creditCard() {
  return const AccountRecord(
    id: 'card-1',
    name: 'Test Credit Card',
    type: AccountType.creditCard,
    initialBalance: 0,
    sortOrder: 10,
  );
}

AccountRecord _cashAccount() {
  return const AccountRecord(
    id: 'cash-1',
    name: 'Cash',
    type: AccountType.cash,
    initialBalance: 0,
    sortOrder: 1,
  );
}

TransactionRecord _expenseTransaction({TransactionType type = TransactionType.expense, String accountName = 'Test Credit Card'}) {
  return TransactionRecord(
    id: 'tx-1',
    type: type,
    amount: 12000,
    category: '電子數碼',
    occurredAt: DateTime(2026, 7, 20, 10, 30),
    accountName: accountName,
    memberName: '自己',
    merchantName: 'Store',
    tagName: '日常',
    note: '',
    currency: CurrencyCode.twd,
  );
}
