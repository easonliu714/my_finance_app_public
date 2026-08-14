import '../account/account_record.dart';
import 'credit_card_installment_service.dart';

enum InstallmentPlanStatus {
  preview,
  active,
  cancelled,
  completed,
}

enum InstallmentScheduleItemStatus {
  pending,
  billed,
  paid,
  cancelled,
}

class InstallmentPlanRecord {
  const InstallmentPlanRecord({
    required this.id,
    required this.scenario,
    required this.cardId,
    required this.cardNameSnapshot,
    required this.currency,
    required this.principal,
    required this.termCount,
    required this.firstStatementDate,
    required this.feeMode,
    required this.totalFee,
    required this.annualRate,
    required this.remainderPolicy,
    required this.originalUnpaidBalance,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.sourceTransactionId,
    this.sourceStatementId,
    this.note = '',
  });

  final String id;
  final CreditCardInstallmentScenario scenario;
  final String cardId;
  final String cardNameSnapshot;
  final CurrencyCode currency;
  final double principal;
  final int termCount;
  final DateTime firstStatementDate;
  final CreditCardInstallmentFeeMode feeMode;
  final double totalFee;
  final double annualRate;
  final CreditCardInstallmentRemainderPolicy remainderPolicy;
  final double originalUnpaidBalance;
  final String? sourceTransactionId;
  final String? sourceStatementId;
  final InstallmentPlanStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String note;

  InstallmentPlanRecord copyWith({
    InstallmentPlanStatus? status,
    DateTime? updatedAt,
  }) {
    return InstallmentPlanRecord(
      id: id,
      scenario: scenario,
      cardId: cardId,
      cardNameSnapshot: cardNameSnapshot,
      currency: currency,
      principal: principal,
      termCount: termCount,
      firstStatementDate: firstStatementDate,
      feeMode: feeMode,
      totalFee: totalFee,
      annualRate: annualRate,
      remainderPolicy: remainderPolicy,
      originalUnpaidBalance: originalUnpaidBalance,
      sourceTransactionId: sourceTransactionId,
      sourceStatementId: sourceStatementId,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      note: note,
    );
  }
}

class InstallmentScheduleItemRecord {
  const InstallmentScheduleItemRecord({
    required this.id,
    required this.planId,
    required this.periodNumber,
    required this.statementDate,
    required this.principal,
    required this.fee,
    required this.totalPayment,
    required this.remainingPrincipalAfterPayment,
    required this.revolvingExposureOffset,
    required this.revolvingExposureAfterOffset,
    required this.status,
    this.generatedTransactionId,
  });

  final String id;
  final String planId;
  final int periodNumber;
  final DateTime statementDate;
  final double principal;
  final double fee;
  final double totalPayment;
  final double remainingPrincipalAfterPayment;
  final double revolvingExposureOffset;
  final double revolvingExposureAfterOffset;
  final String? generatedTransactionId;
  final InstallmentScheduleItemStatus status;

  InstallmentScheduleItemRecord copyWith({
    String? generatedTransactionId,
    bool clearGeneratedTransactionId = false,
    InstallmentScheduleItemStatus? status,
  }) {
    return InstallmentScheduleItemRecord(
      id: id,
      planId: planId,
      periodNumber: periodNumber,
      statementDate: statementDate,
      principal: principal,
      fee: fee,
      totalPayment: totalPayment,
      remainingPrincipalAfterPayment: remainingPrincipalAfterPayment,
      revolvingExposureOffset: revolvingExposureOffset,
      revolvingExposureAfterOffset: revolvingExposureAfterOffset,
      generatedTransactionId: clearGeneratedTransactionId ? null : generatedTransactionId ?? this.generatedTransactionId,
      status: status ?? this.status,
    );
  }
}

sealed class InstallmentRepositoryFailure implements Exception {
  const InstallmentRepositoryFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

class DuplicateInstallmentSourceFailure extends InstallmentRepositoryFailure {
  const DuplicateInstallmentSourceFailure(super.message);
}

class InvalidInstallmentScheduleFailure extends InstallmentRepositoryFailure {
  const InvalidInstallmentScheduleFailure(super.message);
}

class InstallmentPlanNotFoundFailure extends InstallmentRepositoryFailure {
  const InstallmentPlanNotFoundFailure(super.message);
}

class InstallmentScheduleItemNotFoundFailure extends InstallmentRepositoryFailure {
  const InstallmentScheduleItemNotFoundFailure(super.message);
}

class InstallmentPlanCancelBlockedFailure extends InstallmentRepositoryFailure {
  const InstallmentPlanCancelBlockedFailure(super.message);

  @override
  String toString() => '已建立還款紀錄的分期帳無法單獨刪除，請確認。';
}

class InstallmentSchedulePaymentBlockedFailure extends InstallmentRepositoryFailure {
  const InstallmentSchedulePaymentBlockedFailure(super.message);
}

class InstallmentSchedulePaymentReversalBlockedFailure extends InstallmentRepositoryFailure {
  const InstallmentSchedulePaymentReversalBlockedFailure(super.message);

  @override
  String toString() => '此分期繳款狀態無法撤銷，請確認付款紀錄是否仍存在。';
}

abstract interface class CreditCardInstallmentRepository {
  Future<InstallmentPlanRecord> createPlan({
    required CreditCardInstallmentPlanInput input,
    required CreditCardInstallmentSchedule schedule,
  });

  Future<List<InstallmentPlanRecord>> loadPlansByCardId(String cardId, {InstallmentPlanStatus? status});

  Future<List<InstallmentScheduleItemRecord>> loadScheduleItems(String planId);

  Future<void> cancelPlan(String planId);

  Future<void> markScheduleItemPaid({
    required String planId,
    required String scheduleItemId,
    required String generatedTransactionId,
  });

  Future<void> reverseScheduleItemPayment({
    required String planId,
    required String scheduleItemId,
    required String generatedTransactionId,
  });

  Future<InstallmentPlanRecord?> findActivePlanBySourceTransactionId(String sourceTransactionId);

  Future<InstallmentPlanRecord?> findActivePlanBySourceStatementId(String sourceStatementId);
}

class InMemoryCreditCardInstallmentRepository implements CreditCardInstallmentRepository {
  final Map<String, InstallmentPlanRecord> _plans = <String, InstallmentPlanRecord>{};
  final Map<String, List<InstallmentScheduleItemRecord>> _scheduleItemsByPlanId = <String, List<InstallmentScheduleItemRecord>>{};

  @override
  Future<InstallmentPlanRecord> createPlan({
    required CreditCardInstallmentPlanInput input,
    required CreditCardInstallmentSchedule schedule,
  }) async {
    _validateSchedule(input, schedule);
    final sourceTransactionId = input.sourceTransactionId;
    if (sourceTransactionId != null && sourceTransactionId.isNotEmpty) {
      final duplicate = await findActivePlanBySourceTransactionId(sourceTransactionId);
      if (duplicate != null) {
        throw DuplicateInstallmentSourceFailure('Source transaction $sourceTransactionId already has an active installment plan.');
      }
    }
    final sourceStatementId = input.sourceStatementId;
    if (input.scenario == CreditCardInstallmentScenario.postStatementSpecifiedAmount && sourceStatementId != null && sourceStatementId.isNotEmpty) {
      final duplicate = await findActivePlanBySourceStatementId(sourceStatementId);
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
    _plans[plan.id] = plan;
    _scheduleItemsByPlanId[plan.id] = List<InstallmentScheduleItemRecord>.unmodifiable(
      schedule.items.map(
        (item) => InstallmentScheduleItemRecord(
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
    );
    return plan;
  }

  @override
  Future<List<InstallmentPlanRecord>> loadPlansByCardId(String cardId, {InstallmentPlanStatus? status}) async {
    final items = _plans.values.where((plan) => plan.cardId == cardId && (status == null || plan.status == status)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<InstallmentPlanRecord>.unmodifiable(items);
  }

  @override
  Future<List<InstallmentScheduleItemRecord>> loadScheduleItems(String planId) async {
    final items = _scheduleItemsByPlanId[planId] ?? const <InstallmentScheduleItemRecord>[];
    return List<InstallmentScheduleItemRecord>.unmodifiable(items);
  }

  @override
  Future<void> cancelPlan(String planId) async {
    final plan = _plans[planId];
    if (plan == null) {
      throw InstallmentPlanNotFoundFailure('Installment plan $planId not found.');
    }
    final items = _scheduleItemsByPlanId[planId] ?? const <InstallmentScheduleItemRecord>[];
    if (items.any((item) => item.generatedTransactionId != null && item.generatedTransactionId!.isNotEmpty)) {
      throw const InstallmentPlanCancelBlockedFailure('Installment plan already has generated transactions and cannot be hard-cancelled.');
    }
    _plans[planId] = plan.copyWith(status: InstallmentPlanStatus.cancelled, updatedAt: DateTime.now());
    _scheduleItemsByPlanId[planId] = List<InstallmentScheduleItemRecord>.unmodifiable(
      items.map((item) => item.copyWith(status: InstallmentScheduleItemStatus.cancelled)),
    );
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
    final plan = _plans[planId];
    if (plan == null) {
      throw InstallmentPlanNotFoundFailure('Installment plan $planId not found.');
    }
    if (plan.status != InstallmentPlanStatus.active) {
      throw InstallmentSchedulePaymentBlockedFailure('Installment plan $planId is not active.');
    }
    final items = _scheduleItemsByPlanId[planId];
    if (items == null) {
      throw InstallmentScheduleItemNotFoundFailure('Installment schedule item $scheduleItemId not found.');
    }
    final target = items.where((item) => item.id == scheduleItemId).firstOrNull;
    if (target == null) {
      throw InstallmentScheduleItemNotFoundFailure('Installment schedule item $scheduleItemId not found.');
    }
    if (target.status == InstallmentScheduleItemStatus.paid || target.status == InstallmentScheduleItemStatus.cancelled || (target.generatedTransactionId != null && target.generatedTransactionId!.trim().isNotEmpty)) {
      throw InstallmentSchedulePaymentBlockedFailure('Installment schedule item $scheduleItemId is already paid, cancelled, or linked to a generated transaction.');
    }
    final updatedItems = items
        .map(
          (item) => item.id == scheduleItemId
              ? item.copyWith(
                  generatedTransactionId: generatedTransactionId.trim(),
                  status: InstallmentScheduleItemStatus.paid,
                )
              : item,
        )
        .toList(growable: false);
    _scheduleItemsByPlanId[planId] = List<InstallmentScheduleItemRecord>.unmodifiable(updatedItems);
    final isCompleted = updatedItems.every((item) => item.status == InstallmentScheduleItemStatus.paid);
    _plans[planId] = plan.copyWith(
      status: isCompleted ? InstallmentPlanStatus.completed : InstallmentPlanStatus.active,
      updatedAt: DateTime.now(),
    );
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
    final plan = _plans[planId];
    if (plan == null) {
      throw InstallmentPlanNotFoundFailure('Installment plan $planId not found.');
    }
    if (plan.status == InstallmentPlanStatus.cancelled) {
      throw InstallmentSchedulePaymentReversalBlockedFailure('Installment plan $planId is cancelled.');
    }
    final items = _scheduleItemsByPlanId[planId];
    if (items == null) {
      throw InstallmentScheduleItemNotFoundFailure('Installment schedule item $scheduleItemId not found.');
    }
    final target = items.where((item) => item.id == scheduleItemId).firstOrNull;
    if (target == null) {
      throw InstallmentScheduleItemNotFoundFailure('Installment schedule item $scheduleItemId not found.');
    }
    if (target.status != InstallmentScheduleItemStatus.paid || target.generatedTransactionId?.trim() != generatedTransactionId.trim()) {
      throw const InstallmentSchedulePaymentReversalBlockedFailure('Installment schedule item is not linked to the specified generated transaction.');
    }
    final updatedItems = items
        .map(
          (item) => item.id == scheduleItemId
              ? item.copyWith(
                  clearGeneratedTransactionId: true,
                  status: InstallmentScheduleItemStatus.pending,
                )
              : item,
        )
        .toList(growable: false);
    _scheduleItemsByPlanId[planId] = List<InstallmentScheduleItemRecord>.unmodifiable(updatedItems);
    _plans[planId] = plan.copyWith(status: InstallmentPlanStatus.active, updatedAt: DateTime.now());
  }

  @override
  Future<InstallmentPlanRecord?> findActivePlanBySourceTransactionId(String sourceTransactionId) async {
    for (final plan in _plans.values) {
      if (plan.status == InstallmentPlanStatus.active && plan.sourceTransactionId == sourceTransactionId) return plan;
    }
    return null;
  }

  @override
  Future<InstallmentPlanRecord?> findActivePlanBySourceStatementId(String sourceStatementId) async {
    for (final plan in _plans.values) {
      if (plan.status == InstallmentPlanStatus.active && plan.scenario == CreditCardInstallmentScenario.postStatementSpecifiedAmount && plan.sourceStatementId == sourceStatementId) {
        return plan;
      }
    }
    return null;
  }

  void markScheduleItemGeneratedTransactionForTest(String planId, int periodNumber, String transactionId) {
    final items = _scheduleItemsByPlanId[planId];
    if (items == null) return;
    _scheduleItemsByPlanId[planId] = List<InstallmentScheduleItemRecord>.unmodifiable(
      items.map((item) => item.periodNumber == periodNumber ? item.copyWith(generatedTransactionId: transactionId) : item),
    );
  }
}

void _validateSchedule(CreditCardInstallmentPlanInput input, CreditCardInstallmentSchedule schedule) {
  if (!input.isValid) {
    throw const InvalidInstallmentScheduleFailure('Installment input is invalid.');
  }
  if (schedule.items.length != input.termCount) {
    throw const InvalidInstallmentScheduleFailure('Schedule item count does not match term count.');
  }
  if (!_sameMoney(input.currency, schedule.totalPrincipal, input.roundedPrincipal)) {
    throw const InvalidInstallmentScheduleFailure('Schedule total principal does not match input principal.');
  }
  final principalSum = schedule.items.fold<double>(0, (sum, item) => sum + item.principal);
  if (!_sameMoney(input.currency, principalSum, schedule.totalPrincipal)) {
    throw const InvalidInstallmentScheduleFailure('Schedule item principal sum does not match schedule total principal.');
  }
  final feeSum = schedule.items.fold<double>(0, (sum, item) => sum + item.fee);
  if (!_sameMoney(input.currency, feeSum, schedule.totalFee)) {
    throw const InvalidInstallmentScheduleFailure('Schedule item fee sum does not match schedule total fee.');
  }
  for (final item in schedule.items) {
    if (!_sameMoney(input.currency, item.totalPayment, item.principal + item.fee)) {
      throw InvalidInstallmentScheduleFailure('Schedule item ${item.periodNumber} total payment is inconsistent.');
    }
    if (item.periodNumber > 1 && input.currency.roundAmount(item.revolvingExposureOffset) != 0) {
      throw InvalidInstallmentScheduleFailure('Schedule item ${item.periodNumber} has repeated revolving exposure offset.');
    }
  }
}

bool _sameMoney(CurrencyCode currency, double left, double right) => currency.roundAmount(left) == currency.roundAmount(right);
