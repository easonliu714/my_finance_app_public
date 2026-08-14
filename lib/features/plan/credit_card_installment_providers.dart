import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../account/account_repository.dart';
import 'credit_card_installment_repository.dart';
import 'credit_card_installment_repository_factory.dart';
import 'credit_card_installment_service.dart';

final creditCardInstallmentDebugRepositoryModeProvider = StateProvider<CreditCardInstallmentRepositoryMode>((ref) {
  return CreditCardInstallmentRepositoryMode.sqlite;
});

final creditCardInstallmentDebugDatabaseProvider = Provider<Future<Database> Function()>((ref) {
  return () => AccountRepository.instance.database;
});

final creditCardInstallmentRepositoryFactoryProvider = Provider<CreditCardInstallmentRepositoryFactory>((ref) {
  final requestedMode = ref.watch(creditCardInstallmentDebugRepositoryModeProvider);
  if (requestedMode == CreditCardInstallmentRepositoryMode.sqlite) {
    return CreditCardInstallmentRepositoryFactory(
      mode: CreditCardInstallmentRepositoryMode.sqlite,
      databaseProvider: ref.watch(creditCardInstallmentDebugDatabaseProvider),
    );
  }
  return const CreditCardInstallmentRepositoryFactory();
});

final creditCardInstallmentRepositoryProvider = Provider<CreditCardInstallmentRepository>((ref) {
  final factory = ref.watch(creditCardInstallmentRepositoryFactoryProvider);
  return factory.create();
});

final creditCardInstallmentControllerProvider = StateNotifierProvider<CreditCardInstallmentController, AsyncValue<CreditCardInstallmentState>>((ref) {
  final repository = ref.watch(creditCardInstallmentRepositoryProvider);
  return CreditCardInstallmentController(repository);
});

class CreditCardInstallmentState {
  const CreditCardInstallmentState({
    this.selectedCardId,
    this.plans = const <InstallmentPlanRecord>[],
    this.scheduleItemsByPlanId = const <String, List<InstallmentScheduleItemRecord>>{},
    this.previewSchedule,
    this.lastCreatedPlan,
    this.lastMessage = '',
  });

  final String? selectedCardId;
  final List<InstallmentPlanRecord> plans;
  final Map<String, List<InstallmentScheduleItemRecord>> scheduleItemsByPlanId;
  final CreditCardInstallmentSchedule? previewSchedule;
  final InstallmentPlanRecord? lastCreatedPlan;
  final String lastMessage;

  CreditCardInstallmentState copyWith({
    String? selectedCardId,
    List<InstallmentPlanRecord>? plans,
    Map<String, List<InstallmentScheduleItemRecord>>? scheduleItemsByPlanId,
    CreditCardInstallmentSchedule? previewSchedule,
    InstallmentPlanRecord? lastCreatedPlan,
    String? lastMessage,
    bool clearPreview = false,
    bool clearLastCreatedPlan = false,
  }) {
    return CreditCardInstallmentState(
      selectedCardId: selectedCardId ?? this.selectedCardId,
      plans: plans ?? this.plans,
      scheduleItemsByPlanId: scheduleItemsByPlanId ?? this.scheduleItemsByPlanId,
      previewSchedule: clearPreview ? null : previewSchedule ?? this.previewSchedule,
      lastCreatedPlan: clearLastCreatedPlan ? null : lastCreatedPlan ?? this.lastCreatedPlan,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }
}

class CreditCardInstallmentController extends StateNotifier<AsyncValue<CreditCardInstallmentState>> {
  CreditCardInstallmentController(this._repository) : super(const AsyncValue.data(CreditCardInstallmentState()));

  final CreditCardInstallmentRepository _repository;

  CreditCardInstallmentState get _current => state.valueOrNull ?? const CreditCardInstallmentState();

  Future<CreditCardInstallmentSchedule> buildPreview(CreditCardInstallmentPlanInput input) async {
    try {
      final schedule = buildCreditCardInstallmentSchedule(input);
      state = AsyncValue.data(
        _current.copyWith(
          selectedCardId: input.cardId,
          previewSchedule: schedule,
          clearLastCreatedPlan: true,
          lastMessage: '已建立分期試算預覽，不會寫入正式資料。',
        ),
      );
      return schedule;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }

  Future<InstallmentPlanRecord> createActivePlan(CreditCardInstallmentPlanInput input) async {
    try {
      final schedule = buildCreditCardInstallmentSchedule(input);
      final plan = await _repository.createPlan(input: input, schedule: schedule);
      await loadPlansByCardId(input.cardId, status: InstallmentPlanStatus.active);
      state = AsyncValue.data(
        _current.copyWith(
          selectedCardId: input.cardId,
          previewSchedule: schedule,
          lastCreatedPlan: plan,
          lastMessage: '已建立 active 分期 plan。',
        ),
      );
      return plan;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }

  Future<void> loadPlansByCardId(String cardId, {InstallmentPlanStatus? status}) async {
    try {
      final plans = await _repository.loadPlansByCardId(cardId, status: status);
      final scheduleItemsByPlanId = <String, List<InstallmentScheduleItemRecord>>{};
      for (final plan in plans) {
        scheduleItemsByPlanId[plan.id] = await _repository.loadScheduleItems(plan.id);
      }
      state = AsyncValue.data(
        _current.copyWith(
          selectedCardId: cardId,
          plans: List<InstallmentPlanRecord>.unmodifiable(plans),
          scheduleItemsByPlanId: Map<String, List<InstallmentScheduleItemRecord>>.unmodifiable(scheduleItemsByPlanId),
          lastMessage: plans.isEmpty ? '尚無分期 plan。' : '已載入 ${plans.length} 筆分期 plan。',
        ),
      );
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }

  Future<void> cancelPlan(String planId) async {
    final cardId = _current.selectedCardId;
    try {
      await _repository.cancelPlan(planId);
      if (cardId != null) {
        await loadPlansByCardId(cardId, status: InstallmentPlanStatus.active);
      } else {
        state = AsyncValue.data(_current.copyWith(lastMessage: '已取消分期 plan。'));
      }
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }
}
