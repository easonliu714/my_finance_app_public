import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/plan/loan_disbursement_service.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  const target = AccountRecord(
    id: 'bank-1',
    name: '薪轉銀行',
    type: AccountType.bank,
    initialBalance: 0,
    sortOrder: 1,
    currency: CurrencyCode.twd,
  );

  test('builds disbursement income and handling fee expense records', () {
    final loan = AccountRecord(
      id: 'loan-1',
      name: '信貸',
      type: AccountType.loan,
      initialBalance: 0,
      sortOrder: 2,
      currency: CurrencyCode.twd,
      loanPrincipal: 100000,
      loanHandlingFee: 3000,
      loanDisbursementAccountName: target.displayName,
      loanStartDate: DateTime(2026, 5, 25),
    );

    final plan = buildLoanDisbursementPlan(
      loan: loan,
      accounts: const [target],
      groupId: 'group-1',
    );

    expect(plan, isNotNull);
    expect(plan!.grossPrincipal, 100000);
    expect(plan.handlingFee, 3000);
    expect(plan.netReceived, 97000);
    expect(plan.records, hasLength(2));

    final principal = plan.records[0];
    expect(principal.id, 'group-1-principal');
    expect(principal.type, TransactionType.income);
    expect(principal.category, '借貸撥款');
    expect(principal.amount, 100000);
    expect(principal.accountName, target.displayName);
    expect(principal.repaymentGroupId, 'group-1');

    final fee = plan.records[1];
    expect(fee.id, 'group-1-fee');
    expect(fee.type, TransactionType.expense);
    expect(fee.category, '借貸手續費');
    expect(fee.amount, 3000);
    expect(fee.accountName, target.displayName);
    expect(fee.repaymentGroupId, 'group-1');
  });

  test('omits handling fee record when fee is zero', () {
    const loan = AccountRecord(
      id: 'loan-1',
      name: '信貸',
      type: AccountType.loan,
      initialBalance: 0,
      sortOrder: 2,
      currency: CurrencyCode.twd,
      loanPrincipal: 100000,
      loanHandlingFee: 0,
      loanDisbursementAccountName: '薪轉銀行',
    );

    final plan = buildLoanDisbursementPlan(
      loan: loan,
      accounts: const [target],
      groupId: 'group-2',
    );

    expect(plan, isNotNull);
    expect(plan!.records, hasLength(1));
    expect(plan.records.single.category, '借貸撥款');
  });

  test('returns null when loan has no target account', () {
    const loan = AccountRecord(
      id: 'loan-1',
      name: '信貸',
      type: AccountType.loan,
      initialBalance: 0,
      sortOrder: 2,
      currency: CurrencyCode.twd,
      loanPrincipal: 100000,
    );

    final plan = buildLoanDisbursementPlan(
      loan: loan,
      accounts: const [target],
      groupId: 'group-3',
    );

    expect(plan, isNull);
  });
}
