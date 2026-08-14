import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/plan/credit_card_minimum_payment_service.dart';
import 'package:my_finance_app/features/plan/credit_card_revolving_interest_service.dart';
import 'package:my_finance_app/features/plan/credit_card_statement_event.dart';
import 'package:my_finance_app/features/plan/credit_card_statement_event_service.dart';
import 'package:my_finance_app/features/plan/credit_card_statement_service.dart';

void main() {
  test('statement event snapshot preserves statement fields and estimates', () {
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
    final revolving = buildCreditCardRevolvingInterestEstimate(minimum);

    final event = buildCreditCardStatementEventSnapshot(
      statement,
      minimumPaymentEstimate: minimum,
      revolvingInterestEstimate: revolving,
      paidAmountOverride: 2000,
      now: DateTime(2026, 6, 1, 8, 30),
    );

    expect(event.id, 'statement-card-1-20260531');
    expect(event.cardId, 'card-1');
    expect(event.cardName, '測試信用卡');
    expect(event.statementDate, DateTime(2026, 5, 31));
    expect(event.dueDate, DateTime(2026, 6, 15));
    expect(event.totalBalance, 20000);
    expect(event.minimumPayment, 2000);
    expect(event.paidAmount, 2000);
    expect(event.unpaidBalance, 18000);
    expect(event.estimatedRevolvingInterest, revolving.estimatedCycleInterest);
    expect(event.estimatedLateFee, revolving.estimatedLateFee);
    expect(event.isFullyPaid, isFalse);
    expect(event.isBelowMinimum, isFalse);
  });

  test('statement event map roundtrip keeps correction fields', () {
    final event = CreditCardStatementEvent(
      id: 'statement-card-1-20260531',
      cardId: 'card-1',
      cardName: '測試信用卡',
      currency: CurrencyCode.twd,
      statementDate: DateTime(2026, 5, 31),
      dueDate: DateTime(2026, 6, 15),
      periodStart: DateTime(2026, 5, 1),
      periodEnd: DateTime(2026, 5, 31),
      totalBalance: 12000,
      minimumPayment: 1200,
      paidAmount: 500,
      unpaidBalance: 11500,
      estimatedRevolvingInterest: 142,
      estimatedLateFee: 300,
      note: '依銀行帳單校正',
      createdAt: DateTime(2026, 6, 1, 8, 30),
      updatedAt: DateTime(2026, 6, 2, 9, 10),
    );

    final restored = CreditCardStatementEvent.fromMap(event.toMap());

    expect(restored.id, event.id);
    expect(restored.totalBalance, 12000);
    expect(restored.minimumPayment, 1200);
    expect(restored.paidAmount, 500);
    expect(restored.unpaidBalance, 11500);
    expect(restored.estimatedRevolvingInterest, 142);
    expect(restored.estimatedLateFee, 300);
    expect(restored.note, '依銀行帳單校正');
    expect(restored.isBelowMinimum, isTrue);
  });
}
