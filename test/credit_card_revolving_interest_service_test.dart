import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/plan/credit_card_minimum_payment_service.dart';
import 'package:my_finance_app/features/plan/credit_card_revolving_interest_service.dart';
import 'package:my_finance_app/features/plan/credit_card_statement_service.dart';

void main() {
  test('paying only minimum due creates revolving principal and cycle interest estimate', () {
    const card = AccountRecord(
      id: 'card-1',
      name: '測試信用卡',
      type: AccountType.creditCard,
      initialBalance: 0,
      sortOrder: 1,
      currency: CurrencyCode.twd,
    );
    final statement = CreditCardStatementEstimate(
      card: card,
      periodStart: DateTime(2026, 5, 1),
      periodEnd: DateTime(2026, 5, 31),
      dueDate: DateTime(2026, 6, 15),
      purchaseTotal: 20000,
      paymentTotal: 0,
      estimatedDue: 20000,
      outstandingTotal: 20000,
      totalPurchaseCount: 1,
      totalPaymentCount: 0,
      isPaid: false,
      purchaseCount: 1,
      paymentCount: 0,
    );
    final minimum = buildCreditCardMinimumPaymentEstimate(statement);

    final estimate = buildCreditCardRevolvingInterestEstimate(minimum);

    expect(minimum.estimatedMinimumDue, 2000);
    expect(estimate.assumedPaymentAmount, 2000);
    expect(estimate.revolvingPrincipal, 18000);
    expect(estimate.estimatedDailyInterest, greaterThan(0));
    expect(estimate.estimatedCycleInterest, greaterThan(0));
    expect(estimate.estimatedLateFee, 0);
  });

  test('paying below minimum due creates late fee risk estimate', () {
    const card = AccountRecord(
      id: 'card-2',
      name: '未繳足信用卡',
      type: AccountType.creditCard,
      initialBalance: 0,
      sortOrder: 1,
      currency: CurrencyCode.twd,
    );
    final statement = CreditCardStatementEstimate(
      card: card,
      periodStart: DateTime(2026, 5, 1),
      periodEnd: DateTime(2026, 5, 31),
      dueDate: DateTime(2026, 6, 15),
      purchaseTotal: 12000,
      paymentTotal: 0,
      estimatedDue: 12000,
      outstandingTotal: 12000,
      totalPurchaseCount: 1,
      totalPaymentCount: 0,
      isPaid: false,
      purchaseCount: 1,
      paymentCount: 0,
    );
    final minimum = buildCreditCardMinimumPaymentEstimate(statement);

    final estimate = buildCreditCardRevolvingInterestEstimate(minimum, assumedPaymentAmount: 500);

    expect(minimum.estimatedMinimumDue, 1200);
    expect(estimate.minimumPaymentShortfall, 700);
    expect(estimate.estimatedLateFee, 300);
    expect(estimate.hasLateFeeRisk, isTrue);
  });
}
