import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_migration.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_repository.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_service.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_sqlite_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SQLiteCreditCardInstallmentRepository', () {
    test('creates active plan and schedule items', () async {
      final db = await _openDb();
      addTearDown(db.close);
      final repository = SQLiteCreditCardInstallmentRepository(() async => db);
      final input = _input(id: 'plan-1', sourceTransactionId: 'tx-1');
      final schedule = buildCreditCardInstallmentSchedule(input);

      final plan = await repository.createPlan(input: input, schedule: schedule);
      final plans = await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.active);
      final items = await repository.loadScheduleItems('plan-1');

      expect(plan.id, 'plan-1');
      expect(plans.map((item) => item.id), ['plan-1']);
      expect(items, hasLength(6));
      expect(items.first.status, InstallmentScheduleItemStatus.pending);
      final rows = await db.query('credit_card_installment_plans', where: 'id = ?', whereArgs: <Object?>['plan-1']);
      expect(rows.single['source_type'], 'purchase_transaction');
      expect(rows.single['principal_accounting_mode'], 'defer_card_charge');
    });

    test('rejects duplicate active source transaction', () async {
      final db = await _openDb();
      addTearDown(db.close);
      final repository = SQLiteCreditCardInstallmentRepository(() async => db);
      await repository.createPlan(input: _input(id: 'plan-1', sourceTransactionId: 'tx-dup'), schedule: buildCreditCardInstallmentSchedule(_input(id: 'plan-1', sourceTransactionId: 'tx-dup')));

      expect(
        () => repository.createPlan(input: _input(id: 'plan-2', sourceTransactionId: 'tx-dup'), schedule: buildCreditCardInstallmentSchedule(_input(id: 'plan-2', sourceTransactionId: 'tx-dup'))),
        throwsA(isA<DuplicateInstallmentSourceFailure>()),
      );
    });

    test('creates post statement plan and rejects duplicate active source statement', () async {
      final db = await _openDb();
      addTearDown(db.close);
      final repository = SQLiteCreditCardInstallmentRepository(() async => db);
      final input = _postStatementInput(id: 'statement-plan-1', sourceStatementId: 'statement-1');
      await repository.createPlan(input: input, schedule: buildCreditCardInstallmentSchedule(input));
      final items = await repository.loadScheduleItems('statement-plan-1');
      final rows = await db.query('credit_card_installment_plans', where: 'id = ?', whereArgs: <Object?>['statement-plan-1']);

      expect(items.first.revolvingExposureOffset, 12000);
      expect(rows.single['source_type'], 'statement_balance');
      expect(rows.single['expense_recognition_mode'], 'per_period');
      expect(
        () {
          final duplicate = _postStatementInput(id: 'statement-plan-2', sourceStatementId: 'statement-1');
          return repository.createPlan(input: duplicate, schedule: buildCreditCardInstallmentSchedule(duplicate));
        },
        throwsA(isA<DuplicateInstallmentSourceFailure>()),
      );
    });

    test('cancels active plan and schedule items', () async {
      final db = await _openDb();
      addTearDown(db.close);
      final repository = SQLiteCreditCardInstallmentRepository(() async => db);
      final input = _input(id: 'cancel-plan');
      await repository.createPlan(input: input, schedule: buildCreditCardInstallmentSchedule(input));

      await repository.cancelPlan('cancel-plan');
      final activePlans = await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.active);
      final cancelledPlans = await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.cancelled);
      final items = await repository.loadScheduleItems('cancel-plan');

      expect(activePlans, isEmpty);
      expect(cancelledPlans.map((item) => item.id), ['cancel-plan']);
      expect(items.every((item) => item.status == InstallmentScheduleItemStatus.cancelled), isTrue);
    });

    test('blocks cancel when generated transaction exists', () async {
      final db = await _openDb();
      addTearDown(db.close);
      final repository = SQLiteCreditCardInstallmentRepository(() async => db);
      final input = _input(id: 'blocked-plan');
      await repository.createPlan(input: input, schedule: buildCreditCardInstallmentSchedule(input));
      await db.update('credit_card_installment_schedule_items', <String, Object?>{'generated_transaction_id': 'generated-tx-1'}, where: 'plan_id = ? AND period_number = ?', whereArgs: <Object?>['blocked-plan', 1]);

      expect(() => repository.cancelPlan('blocked-plan'), throwsA(isA<InstallmentPlanCancelBlockedFailure>()));
    });

    test('marks schedule item paid and stores generated transaction id', () async {
      final db = await _openDb();
      addTearDown(db.close);
      final repository = SQLiteCreditCardInstallmentRepository(() async => db);
      final input = _input(id: 'paid-plan', termCount: 2);
      await repository.createPlan(input: input, schedule: buildCreditCardInstallmentSchedule(input));

      await repository.markScheduleItemPaid(planId: 'paid-plan', scheduleItemId: 'paid-plan-1', generatedTransactionId: 'generated-tx-1');

      final items = await repository.loadScheduleItems('paid-plan');
      final activePlans = await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.active);
      expect(items.first.status, InstallmentScheduleItemStatus.paid);
      expect(items.first.generatedTransactionId, 'generated-tx-1');
      expect(items.last.status, InstallmentScheduleItemStatus.pending);
      expect(activePlans.map((item) => item.id), ['paid-plan']);
    });

    test('blocks duplicate schedule payment after generated transaction id is attached', () async {
      final db = await _openDb();
      addTearDown(db.close);
      final repository = SQLiteCreditCardInstallmentRepository(() async => db);
      final input = _input(id: 'duplicate-paid-plan', termCount: 2);
      await repository.createPlan(input: input, schedule: buildCreditCardInstallmentSchedule(input));
      await repository.markScheduleItemPaid(planId: 'duplicate-paid-plan', scheduleItemId: 'duplicate-paid-plan-1', generatedTransactionId: 'generated-tx-1');

      expect(
        () => repository.markScheduleItemPaid(planId: 'duplicate-paid-plan', scheduleItemId: 'duplicate-paid-plan-1', generatedTransactionId: 'generated-tx-2'),
        throwsA(isA<InstallmentSchedulePaymentBlockedFailure>()),
      );
    });

    test('marks plan completed after all schedule items are paid', () async {
      final db = await _openDb();
      addTearDown(db.close);
      final repository = SQLiteCreditCardInstallmentRepository(() async => db);
      final input = _input(id: 'completed-plan', termCount: 2);
      await repository.createPlan(input: input, schedule: buildCreditCardInstallmentSchedule(input));

      await repository.markScheduleItemPaid(planId: 'completed-plan', scheduleItemId: 'completed-plan-1', generatedTransactionId: 'generated-tx-1');
      await repository.markScheduleItemPaid(planId: 'completed-plan', scheduleItemId: 'completed-plan-2', generatedTransactionId: 'generated-tx-2');

      final activePlans = await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.active);
      final completedPlans = await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.completed);
      final items = await repository.loadScheduleItems('completed-plan');
      expect(activePlans, isEmpty);
      expect(completedPlans.map((item) => item.id), ['completed-plan']);
      expect(items.every((item) => item.status == InstallmentScheduleItemStatus.paid), isTrue);
    });

    test('reverses paid schedule item back to pending and restores completed plan to active', () async {
      final db = await _openDb();
      addTearDown(db.close);
      final repository = SQLiteCreditCardInstallmentRepository(() async => db);
      final input = _input(id: 'reversal-plan', termCount: 1);
      await repository.createPlan(input: input, schedule: buildCreditCardInstallmentSchedule(input));
      await repository.markScheduleItemPaid(planId: 'reversal-plan', scheduleItemId: 'reversal-plan-1', generatedTransactionId: 'generated-tx-1');

      await repository.reverseScheduleItemPayment(planId: 'reversal-plan', scheduleItemId: 'reversal-plan-1', generatedTransactionId: 'generated-tx-1');

      final activePlans = await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.active);
      final completedPlans = await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.completed);
      final items = await repository.loadScheduleItems('reversal-plan');
      expect(activePlans.map((item) => item.id), ['reversal-plan']);
      expect(completedPlans, isEmpty);
      expect(items.single.status, InstallmentScheduleItemStatus.pending);
      expect(items.single.generatedTransactionId, isNull);
    });

    test('blocks payment reversal when transaction id does not match', () async {
      final db = await _openDb();
      addTearDown(db.close);
      final repository = SQLiteCreditCardInstallmentRepository(() async => db);
      final input = _input(id: 'reversal-block-plan', termCount: 1);
      await repository.createPlan(input: input, schedule: buildCreditCardInstallmentSchedule(input));
      await repository.markScheduleItemPaid(planId: 'reversal-block-plan', scheduleItemId: 'reversal-block-plan-1', generatedTransactionId: 'generated-tx-1');

      expect(
        () => repository.reverseScheduleItemPayment(planId: 'reversal-block-plan', scheduleItemId: 'reversal-block-plan-1', generatedTransactionId: 'wrong-tx'),
        throwsA(isA<InstallmentSchedulePaymentReversalBlockedFailure>()),
      );
    });
  });
}

Future<Database> _openDb() async {
  final db = await openDatabase(inMemoryDatabasePath);
  await createCreditCardInstallmentTables(db);
  return db;
}

CreditCardInstallmentPlanInput _input({required String id, String? sourceTransactionId, int termCount = 6}) {
  return CreditCardInstallmentPlanInput(
    id: id,
    scenario: CreditCardInstallmentScenario.purchaseTime,
    cardId: 'card-1',
    cardName: 'Test Card',
    currency: CurrencyCode.twd,
    principal: 12000,
    termCount: termCount,
    firstStatementDate: DateTime(2026, 7, 5),
    sourceTransactionId: sourceTransactionId,
  );
}

CreditCardInstallmentPlanInput _postStatementInput({required String id, required String sourceStatementId}) {
  return CreditCardInstallmentPlanInput(
    id: id,
    scenario: CreditCardInstallmentScenario.postStatementSpecifiedAmount,
    cardId: 'card-1',
    cardName: 'Test Card',
    currency: CurrencyCode.twd,
    principal: 12000,
    termCount: 6,
    firstStatementDate: DateTime(2026, 7, 5),
    sourceStatementId: sourceStatementId,
    originalUnpaidBalance: 30000,
  );
}
