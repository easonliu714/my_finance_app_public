import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_repository.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_service.dart';

void main() {
  group('InMemoryCreditCardInstallmentRepository', () {
    test('creates purchase-time active plan with schedule items', () async {
      final repository = InMemoryCreditCardInstallmentRepository();
      final input = _input(id: 'plan-1', scenario: CreditCardInstallmentScenario.purchaseTime, principal: 12000, termCount: 6, sourceTransactionId: 'tx-1');
      final schedule = buildCreditCardInstallmentSchedule(input);

      final plan = await repository.createPlan(input: input, schedule: schedule);
      final items = await repository.loadScheduleItems(plan.id);
      final activePlans = await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.active);

      expect(plan.status, InstallmentPlanStatus.active);
      expect(plan.principal, 12000);
      expect(items, hasLength(6));
      expect(items.fold<double>(0, (sum, item) => sum + item.principal), 12000);
      expect(activePlans.map((item) => item.id), ['plan-1']);
    });

    test('rejects duplicate active source transaction', () async {
      final repository = InMemoryCreditCardInstallmentRepository();
      final input = _input(id: 'plan-1', sourceTransactionId: 'tx-dup');
      await repository.createPlan(input: input, schedule: buildCreditCardInstallmentSchedule(input));

      final duplicateInput = _input(id: 'plan-2', sourceTransactionId: 'tx-dup');

      expect(() => repository.createPlan(input: duplicateInput, schedule: buildCreditCardInstallmentSchedule(duplicateInput)), throwsA(isA<DuplicateInstallmentSourceFailure>()));
      expect(await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.active), hasLength(1));
    });

    test('creates post-statement plan with single first-period exposure offset', () async {
      final repository = InMemoryCreditCardInstallmentRepository();
      final input = _input(id: 'plan-post', scenario: CreditCardInstallmentScenario.postStatementSpecifiedAmount, principal: 12000, termCount: 6, originalUnpaidBalance: 15000, sourceStatementId: 'statement-1');

      final plan = await repository.createPlan(input: input, schedule: buildCreditCardInstallmentSchedule(input));
      final items = await repository.loadScheduleItems(plan.id);

      expect(items.first.revolvingExposureOffset, 12000);
      expect(items.first.revolvingExposureAfterOffset, 3000);
      expect(items.skip(1).every((item) => item.revolvingExposureOffset == 0), isTrue);
    });

    test('rejects duplicate active source statement for post-statement installment', () async {
      final repository = InMemoryCreditCardInstallmentRepository();
      final input = _input(id: 'plan-post-1', scenario: CreditCardInstallmentScenario.postStatementSpecifiedAmount, sourceStatementId: 'statement-dup');
      await repository.createPlan(input: input, schedule: buildCreditCardInstallmentSchedule(input));

      final duplicateInput = _input(id: 'plan-post-2', scenario: CreditCardInstallmentScenario.postStatementSpecifiedAmount, sourceStatementId: 'statement-dup');

      expect(() => repository.createPlan(input: duplicateInput, schedule: buildCreditCardInstallmentSchedule(duplicateInput)), throwsA(isA<DuplicateInstallmentSourceFailure>()));
    });

    test('cancels active plan without generated transactions', () async {
      final repository = InMemoryCreditCardInstallmentRepository();
      final input = _input(id: 'plan-cancel');
      await repository.createPlan(input: input, schedule: buildCreditCardInstallmentSchedule(input));

      await repository.cancelPlan('plan-cancel');

      final cancelledPlans = await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.cancelled);
      final activePlans = await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.active);
      final items = await repository.loadScheduleItems('plan-cancel');
      expect(cancelledPlans.map((item) => item.id), ['plan-cancel']);
      expect(activePlans, isEmpty);
      expect(items.every((item) => item.status == InstallmentScheduleItemStatus.cancelled), isTrue);
    });

    test('blocks hard cancel when schedule item already generated a transaction', () async {
      final repository = InMemoryCreditCardInstallmentRepository();
      final input = _input(id: 'plan-blocked-cancel');
      await repository.createPlan(input: input, schedule: buildCreditCardInstallmentSchedule(input));
      repository.markScheduleItemGeneratedTransactionForTest('plan-blocked-cancel', 1, 'generated-tx-1');

      expect(() => repository.cancelPlan('plan-blocked-cancel'), throwsA(isA<InstallmentPlanCancelBlockedFailure>()));
      final activePlans = await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.active);
      expect(activePlans.map((item) => item.id), ['plan-blocked-cancel']);
    });

    test('marks schedule item paid and stores generated transaction id', () async {
      final repository = InMemoryCreditCardInstallmentRepository();
      final input = _input(id: 'plan-paid', termCount: 2);
      await repository.createPlan(input: input, schedule: buildCreditCardInstallmentSchedule(input));

      await repository.markScheduleItemPaid(planId: 'plan-paid', scheduleItemId: 'plan-paid-1', generatedTransactionId: 'generated-tx-1');

      final items = await repository.loadScheduleItems('plan-paid');
      final activePlans = await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.active);
      expect(items.first.status, InstallmentScheduleItemStatus.paid);
      expect(items.first.generatedTransactionId, 'generated-tx-1');
      expect(items.last.status, InstallmentScheduleItemStatus.pending);
      expect(activePlans.map((item) => item.id), ['plan-paid']);
    });

    test('blocks duplicate schedule payment after generated transaction id is attached', () async {
      final repository = InMemoryCreditCardInstallmentRepository();
      final input = _input(id: 'plan-duplicate-payment', termCount: 2);
      await repository.createPlan(input: input, schedule: buildCreditCardInstallmentSchedule(input));
      await repository.markScheduleItemPaid(planId: 'plan-duplicate-payment', scheduleItemId: 'plan-duplicate-payment-1', generatedTransactionId: 'generated-tx-1');

      expect(
        () => repository.markScheduleItemPaid(planId: 'plan-duplicate-payment', scheduleItemId: 'plan-duplicate-payment-1', generatedTransactionId: 'generated-tx-2'),
        throwsA(isA<InstallmentSchedulePaymentBlockedFailure>()),
      );
    });

    test('marks plan completed after all schedule items are paid', () async {
      final repository = InMemoryCreditCardInstallmentRepository();
      final input = _input(id: 'plan-completed', termCount: 2);
      await repository.createPlan(input: input, schedule: buildCreditCardInstallmentSchedule(input));

      await repository.markScheduleItemPaid(planId: 'plan-completed', scheduleItemId: 'plan-completed-1', generatedTransactionId: 'generated-tx-1');
      await repository.markScheduleItemPaid(planId: 'plan-completed', scheduleItemId: 'plan-completed-2', generatedTransactionId: 'generated-tx-2');

      final activePlans = await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.active);
      final completedPlans = await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.completed);
      final items = await repository.loadScheduleItems('plan-completed');
      expect(activePlans, isEmpty);
      expect(completedPlans.map((item) => item.id), ['plan-completed']);
      expect(items.every((item) => item.status == InstallmentScheduleItemStatus.paid), isTrue);
    });

    test('reverses paid schedule item back to pending and restores completed plan to active', () async {
      final repository = InMemoryCreditCardInstallmentRepository();
      final input = _input(id: 'plan-reversal', termCount: 1);
      await repository.createPlan(input: input, schedule: buildCreditCardInstallmentSchedule(input));
      await repository.markScheduleItemPaid(planId: 'plan-reversal', scheduleItemId: 'plan-reversal-1', generatedTransactionId: 'generated-tx-1');

      await repository.reverseScheduleItemPayment(planId: 'plan-reversal', scheduleItemId: 'plan-reversal-1', generatedTransactionId: 'generated-tx-1');

      final activePlans = await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.active);
      final completedPlans = await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.completed);
      final items = await repository.loadScheduleItems('plan-reversal');
      expect(activePlans.map((item) => item.id), ['plan-reversal']);
      expect(completedPlans, isEmpty);
      expect(items.single.status, InstallmentScheduleItemStatus.pending);
      expect(items.single.generatedTransactionId, isNull);
    });

    test('blocks payment reversal when transaction id does not match', () async {
      final repository = InMemoryCreditCardInstallmentRepository();
      final input = _input(id: 'plan-reversal-block', termCount: 1);
      await repository.createPlan(input: input, schedule: buildCreditCardInstallmentSchedule(input));
      await repository.markScheduleItemPaid(planId: 'plan-reversal-block', scheduleItemId: 'plan-reversal-block-1', generatedTransactionId: 'generated-tx-1');

      expect(
        () => repository.reverseScheduleItemPayment(planId: 'plan-reversal-block', scheduleItemId: 'plan-reversal-block-1', generatedTransactionId: 'wrong-tx'),
        throwsA(isA<InstallmentSchedulePaymentReversalBlockedFailure>()),
      );
    });

    test('rejects inconsistent schedule total principal', () async {
      final repository = InMemoryCreditCardInstallmentRepository();
      final input = _input(id: 'plan-invalid');
      final sourceSchedule = buildCreditCardInstallmentSchedule(input);
      final invalidSchedule = CreditCardInstallmentSchedule(input: input, items: sourceSchedule.items, totalPrincipal: 9999, totalFee: sourceSchedule.totalFee, grandTotal: sourceSchedule.grandTotal, immediateRevolvingExposureOffset: sourceSchedule.immediateRevolvingExposureOffset, remainingRevolvingExposureAfterOffset: sourceSchedule.remainingRevolvingExposureAfterOffset);

      expect(() => repository.createPlan(input: input, schedule: invalidSchedule), throwsA(isA<InvalidInstallmentScheduleFailure>()));
    });
  });
}

CreditCardInstallmentPlanInput _input({
  required String id,
  CreditCardInstallmentScenario scenario = CreditCardInstallmentScenario.purchaseTime,
  double principal = 12000,
  int termCount = 6,
  double originalUnpaidBalance = 0,
  String? sourceTransactionId,
  String? sourceStatementId,
}) {
  return CreditCardInstallmentPlanInput(
    id: id,
    scenario: scenario,
    cardId: 'card-1',
    cardName: 'Test Card',
    currency: CurrencyCode.twd,
    principal: principal,
    termCount: termCount,
    firstStatementDate: DateTime(2026, 7, 5),
    originalUnpaidBalance: originalUnpaidBalance,
    sourceTransactionId: sourceTransactionId,
    sourceStatementId: sourceStatementId,
  );
}
