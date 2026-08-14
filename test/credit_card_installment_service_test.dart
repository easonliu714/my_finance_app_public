import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_service.dart';

void main() {
  group('buildCreditCardInstallmentSchedule', () {
    test('splits TWD principal and puts remainder in first period', () {
      final schedule = buildCreditCardInstallmentSchedule(
        CreditCardInstallmentPlanInput(
          id: 'plan-1',
          scenario: CreditCardInstallmentScenario.purchaseTime,
          cardId: 'card-1',
          cardName: 'Card',
          currency: CurrencyCode.twd,
          principal: 10000,
          termCount: 3,
          firstStatementDate: DateTime(2026, 6, 30),
        ),
      );

      expect(schedule.items, hasLength(3));
      expect(schedule.totalPrincipal, 10000);
      expect(schedule.totalFee, 0);
      expect(schedule.grandTotal, 10000);
      expect(schedule.items.map((item) => item.principal), [3334, 3333, 3333]);
      expect(schedule.items.map((item) => item.statementDate.day), [30, 30, 30]);
      expect(schedule.items.last.remainingPrincipalAfterPayment, 0);
      expect(schedule.immediateRevolvingExposureOffset, 0);
    });

    test('supports last-period remainder policy and total-fee split', () {
      final schedule = buildCreditCardInstallmentSchedule(
        CreditCardInstallmentPlanInput(
          id: 'plan-2',
          scenario: CreditCardInstallmentScenario.purchaseTime,
          cardId: 'card-1',
          cardName: 'Card',
          currency: CurrencyCode.twd,
          principal: 10000,
          termCount: 3,
          firstStatementDate: DateTime(2026, 6, 15),
          totalFee: 100,
          remainderPolicy: CreditCardInstallmentRemainderPolicy.lastPeriod,
        ),
      );

      expect(schedule.items.map((item) => item.principal), [3333, 3333, 3334]);
      expect(schedule.items.map((item) => item.fee), [33, 33, 34]);
      expect(schedule.items.map((item) => item.totalPayment), [3366, 3366, 3368]);
      expect(schedule.totalFee, 100);
      expect(schedule.grandTotal, 10100);
    });

    test('estimates annual-rate fee and keeps currency decimal precision', () {
      final schedule = buildCreditCardInstallmentSchedule(
        CreditCardInstallmentPlanInput(
          id: 'plan-3',
          scenario: CreditCardInstallmentScenario.purchaseTime,
          cardId: 'card-1',
          cardName: 'USD Card',
          currency: CurrencyCode.usd,
          principal: 1000,
          termCount: 6,
          firstStatementDate: DateTime(2026, 1, 31),
          feeMode: CreditCardInstallmentFeeMode.annualRate,
          annualRate: 12,
        ),
      );

      expect(schedule.totalFee, 60);
      expect(schedule.grandTotal, 1060);
      expect(schedule.items.map((item) => item.principal), [166.7, 166.66, 166.66, 166.66, 166.66, 166.66]);
      expect(schedule.items.map((item) => item.fee), [10, 10, 10, 10, 10, 10]);
      expect(schedule.items.map((item) => item.statementDate.day), [31, 28, 31, 30, 31, 30]);
    });

    test('post-statement installment offsets revolving exposure once', () {
      final schedule = buildCreditCardInstallmentSchedule(
        CreditCardInstallmentPlanInput(
          id: 'plan-4',
          scenario: CreditCardInstallmentScenario.postStatementSpecifiedAmount,
          cardId: 'card-1',
          cardName: 'Card',
          currency: CurrencyCode.twd,
          principal: 12000,
          termCount: 6,
          firstStatementDate: DateTime(2026, 7, 5),
          originalUnpaidBalance: 15000,
        ),
      );

      expect(schedule.immediateRevolvingExposureOffset, 12000);
      expect(schedule.remainingRevolvingExposureAfterOffset, 3000);
      expect(schedule.items.first.revolvingExposureOffset, 12000);
      expect(schedule.items.first.revolvingExposureAfterOffset, 3000);
      expect(schedule.items.skip(1).every((item) => item.revolvingExposureOffset == 0), isTrue);
    });

    test('post-statement installment caps offset by original unpaid balance', () {
      final schedule = buildCreditCardInstallmentSchedule(
        CreditCardInstallmentPlanInput(
          id: 'plan-5',
          scenario: CreditCardInstallmentScenario.postStatementSpecifiedAmount,
          cardId: 'card-1',
          cardName: 'Card',
          currency: CurrencyCode.twd,
          principal: 12000,
          termCount: 6,
          firstStatementDate: DateTime(2026, 7, 5),
          originalUnpaidBalance: 8000,
        ),
      );

      expect(schedule.immediateRevolvingExposureOffset, 8000);
      expect(schedule.remainingRevolvingExposureAfterOffset, 0);
    });

    test('rejects non-positive principal and term count', () {
      expect(
        () => buildCreditCardInstallmentSchedule(
          CreditCardInstallmentPlanInput(
            id: 'plan-invalid-1',
            scenario: CreditCardInstallmentScenario.purchaseTime,
            cardId: 'card-1',
            cardName: 'Card',
            currency: CurrencyCode.twd,
            principal: 0,
            termCount: 3,
            firstStatementDate: DateTime(2026, 6, 1),
          ),
        ),
        throwsArgumentError,
      );

      expect(
        () => buildCreditCardInstallmentSchedule(
          CreditCardInstallmentPlanInput(
            id: 'plan-invalid-2',
            scenario: CreditCardInstallmentScenario.purchaseTime,
            cardId: 'card-1',
            cardName: 'Card',
            currency: CurrencyCode.twd,
            principal: 1000,
            termCount: 0,
            firstStatementDate: DateTime(2026, 6, 1),
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}
