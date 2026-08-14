import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_payment_preview.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_repository.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_service.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  group('buildInstallmentPaymentTransactionPreview', () {
    test('builds write-safe expense transaction preview for pending schedule item', () {
      final plan = _plan();
      final item = _scheduleItem();
      final result = buildInstallmentPaymentTransactionPreview(
        InstallmentPaymentPreviewInput(plan: plan, scheduleItem: item, paymentAccount: _bankAccount()),
      );

      expect(result.isWriteSafePreview, isTrue);
      expect(result.planId, 'plan-1');
      expect(result.scheduleItemId, 'item-1');
      expect(result.periodNumber, 1);
      expect(result.transaction.id, 'installment-payment-preview-plan-1-1');
      expect(result.transaction.type, TransactionType.expense);
      expect(result.transaction.amount, 2030);
      expect(result.transaction.category, '信用卡分期付款');
      expect(result.transaction.occurredAt, DateTime(2026, 8, 5));
      expect(result.transaction.accountName, '銀行帳戶');
      expect(result.transaction.memberName, '自己');
      expect(result.transaction.merchantName, '不使用商家');
      expect(result.transaction.tagName, '信用卡分期');
      expect(result.transaction.note, contains('Test Credit Card 第 1/6 期'));
      expect(result.transaction.note, contains('plan=plan-1'));
      expect(result.transaction.note, contains('schedule=item-1'));
      expect(result.transaction.currency, CurrencyCode.twd);
      expect(result.transaction.exchangeRateToBase, 1);
    });

    test('allows billed schedule item preview', () {
      final result = buildInstallmentPaymentTransactionPreview(
        InstallmentPaymentPreviewInput(
          plan: _plan(),
          scheduleItem: _scheduleItem(status: InstallmentScheduleItemStatus.billed),
          paymentAccount: _bankAccount(),
        ),
      );

      expect(result.transaction.amount, 2030);
    });

    test('rejects schedule item from another plan', () {
      expect(
        () => buildInstallmentPaymentTransactionPreview(
          InstallmentPaymentPreviewInput(plan: _plan(), scheduleItem: _scheduleItem(planId: 'other-plan'), paymentAccount: _bankAccount()),
        ),
        throwsA(isA<InstallmentPaymentPreviewBlocked>()),
      );
    });

    test('rejects cancelled plan', () {
      expect(
        () => buildInstallmentPaymentTransactionPreview(
          InstallmentPaymentPreviewInput(plan: _plan(status: InstallmentPlanStatus.cancelled), scheduleItem: _scheduleItem(), paymentAccount: _bankAccount()),
        ),
        throwsA(isA<InstallmentPaymentPreviewBlocked>()),
      );
    });

    test('rejects paid or cancelled schedule item', () {
      for (final status in [InstallmentScheduleItemStatus.paid, InstallmentScheduleItemStatus.cancelled]) {
        expect(
          () => buildInstallmentPaymentTransactionPreview(
            InstallmentPaymentPreviewInput(plan: _plan(), scheduleItem: _scheduleItem(status: status), paymentAccount: _bankAccount()),
          ),
          throwsA(isA<InstallmentPaymentPreviewBlocked>()),
        );
      }
    });

    test('rejects schedule item with generated transaction id', () {
      expect(
        () => buildInstallmentPaymentTransactionPreview(
          InstallmentPaymentPreviewInput(plan: _plan(), scheduleItem: _scheduleItem(generatedTransactionId: 'tx-generated'), paymentAccount: _bankAccount()),
        ),
        throwsA(isA<InstallmentPaymentPreviewBlocked>()),
      );
    });

    test('rejects credit card payment account', () {
      expect(
        () => buildInstallmentPaymentTransactionPreview(
          InstallmentPaymentPreviewInput(plan: _plan(), scheduleItem: _scheduleItem(), paymentAccount: _creditCardAccount()),
        ),
        throwsA(isA<InstallmentPaymentPreviewBlocked>()),
      );
    });
  });
}

InstallmentPlanRecord _plan({InstallmentPlanStatus status = InstallmentPlanStatus.active}) {
  return InstallmentPlanRecord(
    id: 'plan-1',
    scenario: CreditCardInstallmentScenario.purchaseTime,
    cardId: 'card-1',
    cardNameSnapshot: 'Test Credit Card',
    currency: CurrencyCode.twd,
    principal: 12000,
    termCount: 6,
    firstStatementDate: DateTime(2026, 8, 5),
    feeMode: CreditCardInstallmentFeeMode.totalFee,
    totalFee: 180,
    annualRate: 0,
    remainderPolicy: CreditCardInstallmentRemainderPolicy.firstPeriod,
    originalUnpaidBalance: 0,
    status: status,
    createdAt: DateTime(2026, 7, 20),
    updatedAt: DateTime(2026, 7, 20),
    sourceTransactionId: 'source-tx-1',
  );
}

InstallmentScheduleItemRecord _scheduleItem({
  String planId = 'plan-1',
  InstallmentScheduleItemStatus status = InstallmentScheduleItemStatus.pending,
  String? generatedTransactionId,
}) {
  return InstallmentScheduleItemRecord(
    id: 'item-1',
    planId: planId,
    periodNumber: 1,
    statementDate: DateTime(2026, 8, 5),
    principal: 2000,
    fee: 30,
    totalPayment: 2030,
    remainingPrincipalAfterPayment: 10000,
    revolvingExposureOffset: 0,
    revolvingExposureAfterOffset: 0,
    generatedTransactionId: generatedTransactionId,
    status: status,
  );
}

AccountRecord _bankAccount() {
  return const AccountRecord(id: 'bank-1', name: '銀行帳戶', type: AccountType.bank, initialBalance: 0, sortOrder: 10);
}

AccountRecord _creditCardAccount() {
  return const AccountRecord(id: 'card-1', name: 'Test Credit Card', type: AccountType.creditCard, initialBalance: 0, sortOrder: 20);
}
