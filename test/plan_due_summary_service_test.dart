import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_repository.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_service.dart';
import 'package:my_finance_app/features/plan/plan_due_summary_service.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  test('credit card due summary excludes source transactions already converted to installment', () {
    final card = _creditCard();
    final sourceTx = _expense(id: 'tx-installment-source', amount: 12000, cardName: card.displayName);
    final normalTx = _expense(id: 'tx-normal', amount: 3000, cardName: card.displayName);
    final summary = buildCreditCardDueSummary(
      creditCards: [card],
      transactions: [sourceTx, normalTx],
      installmentPlans: [_installmentSnapshot(card: card, sourceTransactionId: sourceTx.id, nextPayment: 2000, nextPrincipal: 1900, nextFee: 100)],
    );

    expect(summary.cardCount, 1);
    expect(summary.generalPurchaseDueTwd, 3000);
    expect(summary.installmentDueTwd, 2000);
    expect(summary.excludedInstallmentSourceAmountTwd, 12000);
    expect(summary.totalDueTwd, 5000);
    expect(summary.minimumDueTwd, 1000);
    expect(summary.accounts.single.generalTransactions.map((item) => item.id), ['tx-normal']);
    expect(summary.accounts.single.excludedInstallmentSourceTransactions.map((item) => item.id), ['tx-installment-source']);
  });

  test('loan due summary separates principal and interest', () {
    final loan = _loan();

    final summary = buildLoanDueSummary(loans: [loan]);

    expect(summary.loanCount, 1);
    expect(summary.principalDueTwd, 10000);
    expect(summary.interestDueTwd, 1200);
    expect(summary.totalDueTwd, 11200);
    expect(summary.accounts.single.rows.first.remainingPrincipal, 110000);
  });

  test('loan schedule rows include payment notes from loan repayment transactions', () {
    final loan = _loan();
    final paidTransaction = TransactionRecord(
      id: 'loan-paid-1',
      type: TransactionType.loan,
      amount: 11200,
      category: '還款',
      occurredAt: DateTime(2026, 6, 5),
      accountName: loan.displayName,
      memberName: '自己',
      merchantName: '',
      tagName: '貸款',
      note: '第一期還款',
      repaymentGroupId: 'repayment-1',
    );

    final summary = buildLoanDueSummary(loans: [loan], transactions: [paidTransaction]);

    expect(summary.accounts.single.rows.first.isPaid, isTrue);
    expect(summary.accounts.single.rows.first.paymentNote, '已繳納');
    expect(summary.accounts.single.rows[1].isPaid, isFalse);
    expect(summary.accounts.single.rows[1].paymentNote, '未繳納');
  });
}

AccountRecord _creditCard() {
  return const AccountRecord(
    id: 'card-1',
    name: '信用卡A',
    type: AccountType.creditCard,
    initialBalance: 0,
    sortOrder: 1,
    creditLimit: 100000,
    statementDay: 15,
    paymentDueDay: 25,
  );
}

AccountRecord _loan() {
  return const AccountRecord(
    id: 'loan-1',
    name: '房貸',
    type: AccountType.loan,
    initialBalance: 0,
    sortOrder: 1,
    loanPrincipal: 120000,
    annualInterestRate: 12,
    loanTermMonths: 12,
    loanPaymentDueDay: 5,
    loanStartDate: null,
    loanRepaymentMethod: LoanRepaymentMethod.principalOnly,
  );
}

TransactionRecord _expense({required String id, required double amount, required String cardName}) {
  return TransactionRecord(
    id: id,
    type: TransactionType.expense,
    amount: amount,
    category: '日常',
    occurredAt: DateTime(2026, 5, 1),
    accountName: cardName,
    memberName: '自己',
    merchantName: '商家',
    tagName: '日常',
    note: '',
  );
}

InstallmentPlanScheduleSnapshot _installmentSnapshot({required AccountRecord card, required String sourceTransactionId, required double nextPayment, required double nextPrincipal, required double nextFee}) {
  final now = DateTime(2026, 5, 1);
  return InstallmentPlanScheduleSnapshot(
    plan: InstallmentPlanRecord(
      id: 'plan-1',
      scenario: CreditCardInstallmentScenario.purchaseTime,
      cardId: card.id,
      cardNameSnapshot: card.displayName,
      currency: card.currency,
      principal: 12000,
      termCount: 6,
      firstStatementDate: now,
      feeMode: CreditCardInstallmentFeeMode.totalFee,
      totalFee: 600,
      annualRate: 0,
      remainderPolicy: CreditCardInstallmentRemainderPolicy.firstPeriod,
      originalUnpaidBalance: 0,
      sourceTransactionId: sourceTransactionId,
      status: InstallmentPlanStatus.active,
      createdAt: now,
      updatedAt: now,
    ),
    scheduleItems: [
      InstallmentScheduleItemRecord(
        id: 'plan-1-1',
        planId: 'plan-1',
        periodNumber: 1,
        statementDate: now,
        principal: nextPrincipal,
        fee: nextFee,
        totalPayment: nextPayment,
        remainingPrincipalAfterPayment: 10100,
        revolvingExposureOffset: 0,
        revolvingExposureAfterOffset: 0,
        status: InstallmentScheduleItemStatus.pending,
      ),
    ],
  );
}
