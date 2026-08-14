import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/plan/credit_card_minimum_payment_service.dart';
import 'package:my_finance_app/features/plan/credit_card_statement_service.dart';

void main() {
  test('minimum payment estimate applies default floor when subtotal is below floor', () {
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
      purchaseTotal: 3000,
      paymentTotal: 0,
      estimatedDue: 3000,
      outstandingTotal: 3000,
      totalPurchaseCount: 1,
      totalPaymentCount: 0,
      isPaid: false,
      purchaseCount: 1,
      paymentCount: 0,
    );

    final estimate = buildCreditCardMinimumPaymentEstimate(statement);

    expect(estimate.currentPurchaseComponent, 300);
    expect(estimate.floorAdjustment, 700);
    expect(estimate.estimatedMinimumDue, 1000);
  });

  test('minimum payment estimate is zero when outstanding balance is zero', () {
    const card = AccountRecord(
      id: 'card-2',
      name: '已繳清信用卡',
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
      purchaseTotal: 0,
      paymentTotal: 0,
      estimatedDue: 0,
      outstandingTotal: 0,
      totalPurchaseCount: 0,
      totalPaymentCount: 0,
      isPaid: true,
      purchaseCount: 0,
      paymentCount: 0,
    );

    final estimate = buildCreditCardMinimumPaymentEstimate(statement);

    expect(estimate.isZeroBalance, isTrue);
    expect(estimate.estimatedMinimumDue, 0);
    expect(estimate.floorAdjustment, 0);
  });
}
