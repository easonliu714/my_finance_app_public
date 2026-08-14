import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_debug_checks.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_migration.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_providers.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_repository.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_repository_factory.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_service.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_sqlite_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('creditCardInstallmentRepositoryFactoryProvider override', () {
    test('app provider defaults to sqlite repository when database provider is available', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await createCreditCardInstallmentTables(db);
      final container = ProviderContainer(
        overrides: [
          creditCardInstallmentDebugDatabaseProvider.overrideWithValue(() async => db),
        ],
      );
      addTearDown(container.dispose);

      final repository = container.read(creditCardInstallmentRepositoryProvider);

      expect(repository, isA<SQLiteCreditCardInstallmentRepository>());
    });

    test('factory default remains preview-safe in-memory', () {
      const factory = CreditCardInstallmentRepositoryFactory();

      final repository = factory.create();

      expect(repository, isA<InMemoryCreditCardInstallmentRepository>());
    });

    test('explicit in-memory override remains available for preview-safe tests', () async {
      final container = ProviderContainer(
        overrides: [
          creditCardInstallmentDebugRepositoryModeProvider.overrideWith((ref) => CreditCardInstallmentRepositoryMode.previewSafeInMemory),
        ],
      );
      addTearDown(container.dispose);

      final repository = container.read(creditCardInstallmentRepositoryProvider);

      expect(repository, isA<InMemoryCreditCardInstallmentRepository>());
    });

    test('default sqlite provider persists through recreated provider containers', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await createCreditCardInstallmentTables(db);

      final firstContainer = ProviderContainer(
        overrides: [creditCardInstallmentDebugDatabaseProvider.overrideWithValue(() async => db)],
      );
      addTearDown(firstContainer.dispose);
      final firstController = firstContainer.read(creditCardInstallmentControllerProvider.notifier);
      await firstController.createActivePlan(_input(id: 'sqlite-default-plan', sourceTransactionId: 'tx-default-sqlite'));
      final firstRows = await db.query('credit_card_installment_plans', where: 'id = ?', whereArgs: <Object?>['sqlite-default-plan']);
      expect(firstRows, hasLength(1));

      final secondContainer = ProviderContainer(
        overrides: [creditCardInstallmentDebugDatabaseProvider.overrideWithValue(() async => db)],
      );
      addTearDown(secondContainer.dispose);
      final secondRepository = secondContainer.read(creditCardInstallmentRepositoryProvider);
      final existingPlan = await secondRepository.findActivePlanBySourceTransactionId('tx-default-sqlite');
      final plans = await secondRepository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.active);
      final scheduleRows = await db.query('credit_card_installment_schedule_items', where: 'plan_id = ?', whereArgs: <Object?>['sqlite-default-plan']);

      expect(secondRepository, isA<SQLiteCreditCardInstallmentRepository>());
      expect(existingPlan?.id, 'sqlite-default-plan');
      expect(plans.map((plan) => plan.id), contains('sqlite-default-plan'));
      expect(scheduleRows, hasLength(6));
    });

    test('explicit sqlite override persists through controller provider', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await createCreditCardInstallmentTables(db);
      final container = ProviderContainer(
        overrides: [
          creditCardInstallmentRepositoryFactoryProvider.overrideWithValue(
            CreditCardInstallmentRepositoryFactory(
              mode: CreditCardInstallmentRepositoryMode.sqlite,
              databaseProvider: () async => db,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(creditCardInstallmentControllerProvider.notifier);
      await controller.createActivePlan(_input(id: 'sqlite-provider-plan', sourceTransactionId: 'tx-override'));
      final rows = await db.query('credit_card_installment_plans', where: 'id = ?', whereArgs: <Object?>['sqlite-provider-plan']);
      final scheduleRows = await db.query('credit_card_installment_schedule_items', where: 'plan_id = ?', whereArgs: <Object?>['sqlite-provider-plan']);

      expect(rows, hasLength(1));
      expect(rows.single['source_type'], 'purchase_transaction');
      expect(scheduleRows, hasLength(6));
      expect(container.read(creditCardInstallmentControllerProvider).valueOrNull?.plans.map((item) => item.id), ['sqlite-provider-plan']);
    });

    test('debug sqlite mode is the default repository mode', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await createCreditCardInstallmentTables(db);
      final container = ProviderContainer(
        overrides: [
          creditCardInstallmentDebugDatabaseProvider.overrideWithValue(() async => db),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(creditCardInstallmentDebugRepositoryModeProvider), CreditCardInstallmentRepositoryMode.sqlite);
      expect(container.read(creditCardInstallmentRepositoryProvider), isA<SQLiteCreditCardInstallmentRepository>());
    });

    test('debug sqlite provider persists only installment tables through controller', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await createCreditCardInstallmentTables(db);
      final container = ProviderContainer(
        overrides: [
          creditCardInstallmentDebugDatabaseProvider.overrideWithValue(() async => db),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(creditCardInstallmentControllerProvider.notifier);
      await controller.createActivePlan(_input(id: 'debug-toggle-plan', sourceTransactionId: 'tx-debug-toggle'));

      final planRows = await db.query('credit_card_installment_plans', where: 'id = ?', whereArgs: <Object?>['debug-toggle-plan']);
      final scheduleRows = await db.query('credit_card_installment_schedule_items', where: 'plan_id = ?', whereArgs: <Object?>['debug-toggle-plan']);
      final transactionTableRows = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'transactions'");
      final statementTableRows = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'credit_card_statement_events'");

      expect(planRows, hasLength(1));
      expect(scheduleRows, hasLength(6));
      expect(transactionTableRows, isEmpty);
      expect(statementTableRows, isEmpty);
    });

    test('debug snapshot reports installment counts and side-effect table counts', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await createCreditCardInstallmentTables(db);
      final container = ProviderContainer(
        overrides: [
          creditCardInstallmentDebugDatabaseProvider.overrideWithValue(() async => db),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(creditCardInstallmentControllerProvider.notifier);
      final plan = await controller.createActivePlan(_input(id: 'debug-snapshot-plan', sourceTransactionId: 'tx-debug-snapshot'));
      final beforeCancel = await InstallmentDebugSnapshot.load(db, cardId: plan.cardId);
      await controller.cancelPlan(plan.id);
      final afterCancel = await InstallmentDebugSnapshot.load(db, cardId: plan.cardId);

      expect(beforeCancel.activePlanCount, 1);
      expect(beforeCancel.cancelledPlanCount, 0);
      expect(beforeCancel.scheduleItemCount, 6);
      expect(beforeCancel.transactionCount, 0);
      expect(beforeCancel.statementEventCount, 0);
      expect(beforeCancel.accountEventCount, 0);
      expect(beforeCancel.latestPlanId, 'debug-snapshot-plan');
      expect(beforeCancel.hasInstallmentRows, isTrue);
      expect(beforeCancel.hasSideEffectRows, isFalse);

      expect(afterCancel.activePlanCount, 0);
      expect(afterCancel.cancelledPlanCount, 1);
      expect(afterCancel.scheduleItemCount, 6);
      expect(afterCancel.transactionCount, 0);
      expect(afterCancel.statementEventCount, 0);
      expect(afterCancel.accountEventCount, 0);
      expect(afterCancel.hasSideEffectRows, isFalse);
    });
  });
}

CreditCardInstallmentPlanInput _input({required String id, String? sourceTransactionId}) {
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
