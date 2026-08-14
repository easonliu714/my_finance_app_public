import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_providers.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_repository.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_service.dart';

void main() {
  group('CreditCardInstallmentController', () {
    test('buildPreview creates schedule but does not persist plan', () async {
      final repository = InMemoryCreditCardInstallmentRepository();
      final controller = CreditCardInstallmentController(repository);
      final input = _input(id: 'preview-plan');

      final schedule = await controller.buildPreview(input);
      final plans = await repository.loadPlansByCardId('card-1');
      final state = controller.state.valueOrNull;

      expect(schedule.items, hasLength(6));
      expect(plans, isEmpty);
      expect(state?.previewSchedule?.input.id, 'preview-plan');
      expect(state?.lastCreatedPlan, isNull);
    });

    test('createActivePlan persists plan and reloads active plans', () async {
      final repository = InMemoryCreditCardInstallmentRepository();
      final controller = CreditCardInstallmentController(repository);
      final input = _input(id: 'active-plan', sourceTransactionId: 'tx-1');

      final plan = await controller.createActivePlan(input);
      final state = controller.state.valueOrNull;

      expect(plan.status, InstallmentPlanStatus.active);
      expect(state?.plans.map((item) => item.id), ['active-plan']);
      expect(state?.scheduleItemsByPlanId['active-plan'], hasLength(6));
      expect(state?.lastCreatedPlan?.id, 'active-plan');
    });

    test('cancelPlan removes active plan from active query state', () async {
      final repository = InMemoryCreditCardInstallmentRepository();
      final controller = CreditCardInstallmentController(repository);
      final input = _input(id: 'cancel-plan');
      await controller.createActivePlan(input);

      await controller.cancelPlan('cancel-plan');

      final state = controller.state.valueOrNull;
      final cancelledPlans = await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.cancelled);
      expect(state?.plans, isEmpty);
      expect(cancelledPlans.map((item) => item.id), ['cancel-plan']);
    });

    test('createActivePlan surfaces duplicate source failure', () async {
      final repository = InMemoryCreditCardInstallmentRepository();
      final controller = CreditCardInstallmentController(repository);
      await controller.createActivePlan(_input(id: 'plan-1', sourceTransactionId: 'tx-dup'));

      await expectLater(
        controller.createActivePlan(_input(id: 'plan-2', sourceTransactionId: 'tx-dup')),
        throwsA(isA<DuplicateInstallmentSourceFailure>()),
      );
      expect(controller.state.hasError, isTrue);
    });
  });
}

CreditCardInstallmentPlanInput _input({
  required String id,
  String? sourceTransactionId,
}) {
  return CreditCardInstallmentPlanInput(
    id: id,
    scenario: CreditCardInstallmentScenario.purchaseTime,
    cardId: 'card-1',
    cardName: 'Test Card',
    currency: CurrencyCode.twd,
    principal: 12000,
    termCount: 6,
    firstStatementDate: DateTime(2026, 7, 5),
    sourceTransactionId: sourceTransactionId,
  );
}
