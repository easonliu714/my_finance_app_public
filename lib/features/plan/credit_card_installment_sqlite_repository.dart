import 'package:sqflite/sqflite.dart';

import '../account/account_record.dart';
import 'credit_card_installment_migration.dart';
import 'credit_card_installment_repository.dart';
import 'credit_card_installment_service.dart';
import 'credit_card_installment_source.dart';

class SQLiteCreditCardInstallmentRepository implements CreditCardInstallmentRepository {
  SQLiteCreditCardInstallmentRepository(this._databaseProvider);

  final Future<Database> Function() _databaseProvider;

  Future<Database> get _database async {
    final db = await _databaseProvider();
    await upgradeCreditCardInstallmentTablesToV12(db);
    return db;
  }

  @override
  Future<InstallmentPlanRecord> createPlan({
    required CreditCardInstallmentPlanInput input,
    required CreditCardInstallmentSchedule schedule,
  }) async {
    _validateSchedule(input, schedule);
    final db = await _database;
    return db.transaction((txn) async {
      final sourceTransactionId = input.sourceTransactionId;
      if (_hasValue(sourceTransactionId)) {
        final duplicate = await _findActivePlanBySourceTransactionId(txn, sourceTransactionId!);
        if (duplicate != null) {
          throw DuplicateInstallmentSourceFailure('Source transaction $sourceTransactionId already has an active installment plan.');
        }
      }
      final sourceStatementId = input.sourceStatementId;
      if (input.scenario == CreditCardInstallmentScenario.postStatementSpecifiedAmount && _hasValue(sourceStatementId)) {
        final duplicate = await _findActivePlanBySourceStatementId(txn, sourceStatementId!);
        if (duplicate != null) {
          throw DuplicateInstallmentSourceFailure('Source statement $sourceStatementId already has an active post-statement installment plan.');
        }
      }

      final now = DateTime.now();
      final plan = InstallmentPlanRecord(
        id: input.id,
        scenario: input.scenario,
        cardId: input.cardId,
        cardNameSnapshot: input.cardName,
        currency: input.currency,
        principal: schedule.totalPrincipal,
        termCount: input.termCount,
        firstStatementDate: input.firstStatementDate,
        feeMode: input.feeMode,
        totalFee: schedule.totalFee,
        annualRate: input.annualRate,
        remainderPolicy: input.remainderPolicy,
        originalUnpaidBalance: input.roundedOriginalUnpaidBalance,
        sourceTransactionId: sourceTransactionId,
        sourceStatementId: sourceStatementId,
        status: InstallmentPlanStatus.active,
        createdAt: now,
        updatedAt: now,
        note: input.note,
      );
      await txn.insert('credit_card_installment_plans', _planToMap(plan), conflictAlgorithm: ConflictAlgorithm.abort);
      for (final item in schedule.items) {
        await txn.insert(
          'credit_card_installment_schedule_items',
          _scheduleItemToMap(
            InstallmentScheduleItemRecord(
              id: '${plan.id}-${item.periodNumber}',
              planId: plan.id,
              periodNumber: item.periodNumber,
              statementDate: item.statementDate,
              principal: item.principal,
              fee: item.fee,
              totalPayment: item.totalPayment,
              remainingPrincipalAfterPayment: item.remainingPrincipalAfterPayment,
              revolvingExposureOffset: item.revolvingExposureOffset,
              revolvingExposureAfterOffset: item.revolvingExposureAfterOffset,
              status: InstallmentScheduleItemStatus.pending,
            ),
          ),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      return plan;
    });
  }

  @override
  Future<List<InstallmentPlanRecord>> loadPlansByCardId(String cardId, {InstallmentPlanStatus? status}) async {
    final db = await _database;
    final rows = await db.query(
      'credit_card_installment_plans',
      where: status == null ? 'card_id = ?' : 'card_id = ? AND status = ?',
      whereArgs: status == null ? <Object?>[cardId] : <Object?>[cardId, status.name],
      orderBy: 'created_at DESC',
    );
    return rows.map(_planFromMap).toList(growable: false);
  }

  @override
  Future<List<InstallmentScheduleItemRecord>> loadScheduleItems(String planId) async {
    final db = await _database;
    final rows = await db.query(
      'credit_card_installment_schedule_items',
      where: 'plan_id = ?',
      whereArgs: <Object?>[planId],
      orderBy: 'period_number ASC',
    );
    return rows.map(_scheduleItemFromMap).toList(growable: false);
  }

  @override
  Future<void> cancelPlan(String planId) async {
    final db = await _database;
    await db.transaction((txn) async {
      final plans = await txn.query('credit_card_installment_plans', where: 'id = ?', whereArgs: <Object?>[planId], limit: 1);
      if (plans.isEmpty) throw InstallmentPlanNotFoundFailure('Installment plan $planId not found.');
      final generatedRows = await txn.query(
        'credit_card_installment_schedule_items',
        columns: <String>['id'],
        where: 'plan_id = ? AND generated_transaction_id IS NOT NULL AND generated_transaction_id != ?',
        whereArgs: <Object?>[planId, ''],
        limit: 1,
      );
      if (generatedRows.isNotEmpty) {
        throw const InstallmentPlanCancelBlockedFailure('Installment plan already has generated transactions and cannot be hard-cancelled.');
      }
      final now = DateTime.now().toIso8601String();
      await txn.update('credit_card_installment_plans', <String, Object?>{'status': InstallmentPlanStatus.cancelled.name, 'updated_at': now}, where: 'id = ?', whereArgs: <Object?>[planId]);
      await txn.update('credit_card_installment_schedule_items', <String, Object?>{'status': InstallmentScheduleItemStatus.cancelled.name, 'updated_at': now}, where: 'plan_id = ?', whereArgs: <Object?>[planId]);
    });
  }

  @override
  Future<void> markScheduleItemPaid({
    required String planId,
    required String scheduleItemId,
    required String generatedTransactionId,
  }) async {
    if (generatedTransactionId.trim().isEmpty) {
      throw const InstallmentSchedulePaymentBlockedFailure('Generated transaction id is required to mark an installment schedule item paid.');
    }
    final db = await _database;
    await db.transaction((txn) async {
      final planRows = await txn.query('credit_card_installment_plans', where: 'id = ?', whereArgs: <Object?>[planId], limit: 1);
      if (planRows.isEmpty) throw InstallmentPlanNotFoundFailure('Installment plan $planId not found.');
      final plan = _planFromMap(planRows.first);
      if (plan.status != InstallmentPlanStatus.active) {
        throw InstallmentSchedulePaymentBlockedFailure('Installment plan $planId is not active.');
      }
      final itemRows = await txn.query('credit_card_installment_schedule_items', where: 'id = ? AND plan_id = ?', whereArgs: <Object?>[scheduleItemId, planId], limit: 1);
      if (itemRows.isEmpty) {
        throw InstallmentScheduleItemNotFoundFailure('Installment schedule item $scheduleItemId not found.');
      }
      final item = _scheduleItemFromMap(itemRows.first);
      if (item.status == InstallmentScheduleItemStatus.paid || item.status == InstallmentScheduleItemStatus.cancelled || _hasValue(item.generatedTransactionId)) {
        throw InstallmentSchedulePaymentBlockedFailure('Installment schedule item $scheduleItemId is already paid, cancelled, or linked to a generated transaction.');
      }
      final now = DateTime.now().toIso8601String();
      await txn.update(
        'credit_card_installment_schedule_items',
        <String, Object?>{
          'status': InstallmentScheduleItemStatus.paid.name,
          'generated_transaction_id': generatedTransactionId.trim(),
          'updated_at': now,
        },
        where: 'id = ? AND plan_id = ?',
        whereArgs: <Object?>[scheduleItemId, planId],
      );
      final remainingRows = await txn.query(
        'credit_card_installment_schedule_items',
        columns: <String>['id'],
        where: 'plan_id = ? AND status != ?',
        whereArgs: <Object?>[planId, InstallmentScheduleItemStatus.paid.name],
        limit: 1,
      );
      await txn.update(
        'credit_card_installment_plans',
        <String, Object?>{
          'status': remainingRows.isEmpty ? InstallmentPlanStatus.completed.name : InstallmentPlanStatus.active.name,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: <Object?>[planId],
      );
    });
  }

  @override
  Future<void> reverseScheduleItemPayment({
    required String planId,
    required String scheduleItemId,
    required String generatedTransactionId,
  }) async {
    if (generatedTransactionId.trim().isEmpty) {
      throw const InstallmentSchedulePaymentReversalBlockedFailure('Generated transaction id is required to reverse an installment schedule payment.');
    }
    final db = await _database;
    await db.transaction((txn) async {
      final planRows = await txn.query('credit_card_installment_plans', where: 'id = ?', whereArgs: <Object?>[planId], limit: 1);
      if (planRows.isEmpty) throw InstallmentPlanNotFoundFailure('Installment plan $planId not found.');
      final plan = _planFromMap(planRows.first);
      if (plan.status == InstallmentPlanStatus.cancelled) {
        throw InstallmentSchedulePaymentReversalBlockedFailure('Installment plan $planId is cancelled.');
      }
      final itemRows = await txn.query('credit_card_installment_schedule_items', where: 'id = ? AND plan_id = ?', whereArgs: <Object?>[scheduleItemId, planId], limit: 1);
      if (itemRows.isEmpty) {
        throw InstallmentScheduleItemNotFoundFailure('Installment schedule item $scheduleItemId not found.');
      }
      final item = _scheduleItemFromMap(itemRows.first);
      if (item.status != InstallmentScheduleItemStatus.paid || item.generatedTransactionId?.trim() != generatedTransactionId.trim()) {
        throw const InstallmentSchedulePaymentReversalBlockedFailure('Installment schedule item is not linked to the specified generated transaction.');
      }
      final now = DateTime.now().toIso8601String();
      await txn.update(
        'credit_card_installment_schedule_items',
        <String, Object?>{
          'status': InstallmentScheduleItemStatus.pending.name,
          'generated_transaction_id': null,
          'updated_at': now,
        },
        where: 'id = ? AND plan_id = ?',
        whereArgs: <Object?>[scheduleItemId, planId],
      );
      await txn.update(
        'credit_card_installment_plans',
        <String, Object?>{
          'status': InstallmentPlanStatus.active.name,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: <Object?>[planId],
      );
    });
  }

  @override
  Future<InstallmentPlanRecord?> findActivePlanBySourceTransactionId(String sourceTransactionId) async {
    final db = await _database;
    return _findActivePlanBySourceTransactionId(db, sourceTransactionId);
  }

  @override
  Future<InstallmentPlanRecord?> findActivePlanBySourceStatementId(String sourceStatementId) async {
    final db = await _database;
    return _findActivePlanBySourceStatementId(db, sourceStatementId);
  }

  Future<InstallmentPlanRecord?> _findActivePlanBySourceTransactionId(DatabaseExecutor db, String sourceTransactionId) async {
    final rows = await db.query(
      'credit_card_installment_plans',
      where: 'source_transaction_id = ? AND status = ?',
      whereArgs: <Object?>[sourceTransactionId, InstallmentPlanStatus.active.name],
      limit: 1,
    );
    return rows.isEmpty ? null : _planFromMap(rows.first);
  }

  Future<InstallmentPlanRecord?> _findActivePlanBySourceStatementId(DatabaseExecutor db, String sourceStatementId) async {
    final rows = await db.query(
      'credit_card_installment_plans',
      where: 'source_statement_id = ? AND status = ?',
      whereArgs: <Object?>[sourceStatementId, InstallmentPlanStatus.active.name],
      limit: 1,
    );
    return rows.isEmpty ? null : _planFromMap(rows.first);
  }
}

Map<String, Object?> _planToMap(InstallmentPlanRecord plan) => <String, Object?>{
      'id': plan.id,
      'scenario': plan.scenario.name,
      'card_id': plan.cardId,
      'card_name_snapshot': plan.cardNameSnapshot,
      'currency_code': plan.currency.code,
      'principal': plan.principal,
      'term_count': plan.termCount,
      'first_statement_date': plan.firstStatementDate.toIso8601String(),
      'fee_mode': plan.feeMode.name,
      'total_fee': plan.totalFee,
      'annual_rate': plan.annualRate,
      'remainder_policy': plan.remainderPolicy.name,
      'original_unpaid_balance': plan.originalUnpaidBalance,
      'source_transaction_id': plan.sourceTransactionId,
      'source_statement_id': plan.sourceStatementId,
      'source_type': plan.inferredSourceType.code,
      'expense_recognition_mode': plan.inferredExpenseRecognitionMode.code,
      'principal_accounting_mode': plan.inferredPrincipalAccountingMode.code,
      'status': plan.status.name,
      'note': plan.note,
      'created_at': plan.createdAt.toIso8601String(),
      'updated_at': plan.updatedAt.toIso8601String(),
    };

Map<String, Object?> _scheduleItemToMap(InstallmentScheduleItemRecord item) => <String, Object?>{
      'id': item.id,
      'plan_id': item.planId,
      'period_number': item.periodNumber,
      'statement_date': item.statementDate.toIso8601String(),
      'principal': item.principal,
      'fee': item.fee,
      'total_payment': item.totalPayment,
      'remaining_principal_after_payment': item.remainingPrincipalAfterPayment,
      'revolving_exposure_offset': item.revolvingExposureOffset,
      'revolving_exposure_after_offset': item.revolvingExposureAfterOffset,
      'generated_transaction_id': item.generatedTransactionId,
      'status': item.status.name,
    };

InstallmentPlanRecord _planFromMap(Map<String, Object?> map) => InstallmentPlanRecord(
      id: map['id'] as String,
      scenario: _enumByName(CreditCardInstallmentScenario.values, map['scenario'] as String?, CreditCardInstallmentScenario.purchaseTime),
      cardId: map['card_id'] as String,
      cardNameSnapshot: map['card_name_snapshot'] as String? ?? '',
      currency: currencyFromCode(map['currency_code'] as String?),
      principal: _doubleValue(map['principal']),
      termCount: _intValue(map['term_count']),
      firstStatementDate: DateTime.tryParse(map['first_statement_date'] as String? ?? '') ?? DateTime(2000),
      feeMode: _enumByName(CreditCardInstallmentFeeMode.values, map['fee_mode'] as String?, CreditCardInstallmentFeeMode.totalFee),
      totalFee: _doubleValue(map['total_fee']),
      annualRate: _doubleValue(map['annual_rate']),
      remainderPolicy: _enumByName(CreditCardInstallmentRemainderPolicy.values, map['remainder_policy'] as String?, CreditCardInstallmentRemainderPolicy.firstPeriod),
      originalUnpaidBalance: _doubleValue(map['original_unpaid_balance']),
      sourceTransactionId: map['source_transaction_id'] as String?,
      sourceStatementId: map['source_statement_id'] as String?,
      status: _enumByName(InstallmentPlanStatus.values, map['status'] as String?, InstallmentPlanStatus.active),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime(2000),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime(2000),
      note: map['note'] as String? ?? '',
    );

InstallmentScheduleItemRecord _scheduleItemFromMap(Map<String, Object?> map) => InstallmentScheduleItemRecord(
      id: map['id'] as String,
      planId: map['plan_id'] as String,
      periodNumber: _intValue(map['period_number']),
      statementDate: DateTime.tryParse(map['statement_date'] as String? ?? '') ?? DateTime(2000),
      principal: _doubleValue(map['principal']),
      fee: _doubleValue(map['fee']),
      totalPayment: _doubleValue(map['total_payment']),
      remainingPrincipalAfterPayment: _doubleValue(map['remaining_principal_after_payment']),
      revolvingExposureOffset: _doubleValue(map['revolving_exposure_offset']),
      revolvingExposureAfterOffset: _doubleValue(map['revolving_exposure_after_offset']),
      generatedTransactionId: map['generated_transaction_id'] as String?,
      status: _enumByName(InstallmentScheduleItemStatus.values, map['status'] as String?, InstallmentScheduleItemStatus.pending),
    );

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) => values.firstWhere((item) => item.name == name, orElse: () => fallback);

bool _hasValue(String? value) => value != null && value.trim().isNotEmpty;

double _doubleValue(Object? value) => value is num ? value.toDouble() : 0;

int _intValue(Object? value) => value is num ? value.toInt() : 0;

void _validateSchedule(CreditCardInstallmentPlanInput input, CreditCardInstallmentSchedule schedule) {
  if (!input.isValid) throw const InvalidInstallmentScheduleFailure('Installment input is invalid.');
  if (schedule.items.length != input.termCount) throw const InvalidInstallmentScheduleFailure('Schedule item count does not match term count.');
  if (!_sameMoney(input.currency, schedule.totalPrincipal, input.roundedPrincipal)) throw const InvalidInstallmentScheduleFailure('Schedule total principal does not match input principal.');
  final principalSum = schedule.items.fold<double>(0, (sum, item) => sum + item.principal);
  if (!_sameMoney(input.currency, principalSum, schedule.totalPrincipal)) throw const InvalidInstallmentScheduleFailure('Schedule item principal sum does not match schedule total principal.');
  final feeSum = schedule.items.fold<double>(0, (sum, item) => sum + item.fee);
  if (!_sameMoney(input.currency, feeSum, schedule.totalFee)) throw const InvalidInstallmentScheduleFailure('Schedule item fee sum does not match schedule total fee.');
  for (final item in schedule.items) {
    if (!_sameMoney(input.currency, item.totalPayment, item.principal + item.fee)) throw InvalidInstallmentScheduleFailure('Schedule item ${item.periodNumber} total payment is inconsistent.');
    if (item.periodNumber > 1 && input.currency.roundAmount(item.revolvingExposureOffset) != 0) throw InvalidInstallmentScheduleFailure('Schedule item ${item.periodNumber} has repeated revolving exposure offset.');
  }
}

bool _sameMoney(CurrencyCode currency, double left, double right) => currency.roundAmount(left) == currency.roundAmount(right);
