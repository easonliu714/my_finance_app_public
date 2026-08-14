import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../plan/credit_card_installment_payment_link.dart';
import '../plan/credit_card_installment_providers.dart';
import '../plan/credit_card_installment_repository.dart';
import 'transaction_ledger_refresh_signal.dart';
import 'transaction_record.dart';
import 'auto_top_up_transaction_store.dart';
import 'transaction_store.dart';

final transactionStoreProvider = Provider<TransactionStore>((ref) {
  return AutoTopUpTransactionStore.instance;
});

final transactionLedgerProvider =
    StateNotifierProvider<
      TransactionLedgerController,
      AsyncValue<TransactionLedgerState>
    >((ref) {
      final store = ref.watch(transactionStoreProvider);
      final installmentRepository = ref.watch(
        creditCardInstallmentRepositoryProvider,
      );
      final controller = TransactionLedgerController(
        store,
        installmentRepository: installmentRepository,
      );
      final subscription = TransactionLedgerRefreshSignal.instance.stream
          .listen((_) {
            controller.load();
          });
      ref.onDispose(subscription.cancel);
      controller.load();
      return controller;
    });

class TransactionLedgerState {
  const TransactionLedgerState({
    required this.records,
    required this.monthlyIncome,
    required this.monthlyExpense,
  });

  final List<TransactionRecord> records;
  final double monthlyIncome;
  final double monthlyExpense;

  double get monthlyBalance => monthlyIncome - monthlyExpense;
}

enum LinkedInstallmentSourceDeleteAction {
  none,
  cancelWithSource,
  blockedExecuted,
}

class LinkedInstallmentSourceDeletePreview {
  const LinkedInstallmentSourceDeletePreview({
    required this.action,
    this.planId,
    this.planLabel,
    this.scheduleCount = 0,
    this.executedScheduleCount = 0,
  });

  const LinkedInstallmentSourceDeletePreview.none()
    : action = LinkedInstallmentSourceDeleteAction.none,
      planId = null,
      planLabel = null,
      scheduleCount = 0,
      executedScheduleCount = 0;

  final LinkedInstallmentSourceDeleteAction action;
  final String? planId;
  final String? planLabel;
  final int scheduleCount;
  final int executedScheduleCount;

  bool get hasLinkedPlan => action != LinkedInstallmentSourceDeleteAction.none;
  bool get canDeleteWithPlanCancel =>
      action == LinkedInstallmentSourceDeleteAction.cancelWithSource;
  bool get isBlocked =>
      action == LinkedInstallmentSourceDeleteAction.blockedExecuted;
}

class TransactionLinkedInstallmentDeleteBlocked implements Exception {
  const TransactionLinkedInstallmentDeleteBlocked(this.message);
  final String message;

  @override
  String toString() => message;
}

class TransactionLedgerController
    extends StateNotifier<AsyncValue<TransactionLedgerState>> {
  TransactionLedgerController(
    this._store, {
    required CreditCardInstallmentRepository installmentRepository,
  }) : _installmentRepository = installmentRepository,
       super(const AsyncValue.loading());

  final TransactionStore _store;
  final CreditCardInstallmentRepository _installmentRepository;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final now = DateTime.now();
      final records = await _store.listRecent();
      final income = await _store.monthlyIncome(now);
      final expense = await _store.monthlyExpense(now);
      state = AsyncValue.data(
        TransactionLedgerState(
          records: records,
          monthlyIncome: income,
          monthlyExpense: expense,
        ),
      );
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> add(TransactionRecord record) async {
    await _store.insert(record);
    await load();
  }

  Future<void> updateRecord(TransactionRecord record) async {
    await _store.update(record);
    await load();
  }

  Future<void> duplicate(TransactionRecord record) async {
    final copied = record.copyWith(
      id: const Uuid().v4(),
      occurredAt: DateTime.now(),
      note: record.note.isEmpty
          ? '複製自 ${record.category}'
          : '${record.note}・複製',
      repaymentGroupId: record.repaymentGroupId == null
          ? null
          : const Uuid().v4(),
    );
    await _store.insert(copied);
    await load();
  }

  Future<LinkedInstallmentSourceDeletePreview>
  previewLinkedInstallmentSourceDeletion(String transactionId) async {
    final plan = await _installmentRepository
        .findActivePlanBySourceTransactionId(transactionId);
    if (plan == null) return const LinkedInstallmentSourceDeletePreview.none();
    final scheduleItems = await _installmentRepository.loadScheduleItems(
      plan.id,
    );
    final executedScheduleCount = scheduleItems
        .where(_isExecutedInstallmentScheduleItem)
        .length;
    final action = executedScheduleCount > 0
        ? LinkedInstallmentSourceDeleteAction.blockedExecuted
        : LinkedInstallmentSourceDeleteAction.cancelWithSource;
    return LinkedInstallmentSourceDeletePreview(
      action: action,
      planId: plan.id,
      planLabel: '${plan.cardNameSnapshot}・${plan.termCount} 期分期',
      scheduleCount: scheduleItems.length,
      executedScheduleCount: executedScheduleCount,
    );
  }

  Future<void> delete(String id) async {
    final records =
        state.valueOrNull?.records ?? await _store.listRecent(limit: 500);
    final record = records.where((item) => item.id == id).firstOrNull;
    await _reverseInstallmentPaymentIfNeeded(record);
    await _guardAndCancelLinkedInstallment(id);
    await _store.deleteById(id);
    await load();
  }

  Future<void> deleteLinkedInstallmentPayment({
    required String planId,
    required String scheduleItemId,
    required String generatedTransactionId,
  }) async {
    await _installmentRepository.reverseScheduleItemPayment(
      planId: planId,
      scheduleItemId: scheduleItemId,
      generatedTransactionId: generatedTransactionId,
    );
    await _store.deleteById(generatedTransactionId);
    await load();
  }

  Future<void> deleteRepaymentGroup(String repaymentGroupId) async {
    await _store.deleteByRepaymentGroupId(repaymentGroupId);
    await load();
  }

  Future<void> deleteLoanRepaymentCluster(TransactionRecord record) async {
    await _store.deleteLoanRepaymentCluster(record);
    await load();
  }

  Future<void> _reverseInstallmentPaymentIfNeeded(
    TransactionRecord? record,
  ) async {
    if (record == null) return;
    final link = parseCreditCardInstallmentPaymentLink(record);
    if (link == null) return;
    await _installmentRepository.reverseScheduleItemPayment(
      planId: link.planId,
      scheduleItemId: link.scheduleItemId,
      generatedTransactionId: link.generatedTransactionId,
    );
  }

  Future<void> _guardAndCancelLinkedInstallment(String transactionId) async {
    final plan = await _installmentRepository
        .findActivePlanBySourceTransactionId(transactionId);
    if (plan == null) return;
    final scheduleItems = await _installmentRepository.loadScheduleItems(
      plan.id,
    );
    final hasExecutedSchedule = scheduleItems.any(
      _isExecutedInstallmentScheduleItem,
    );
    if (hasExecutedSchedule) {
      throw const TransactionLinkedInstallmentDeleteBlocked(
        '這筆信用卡消費已建立分期，且已有還款紀錄，不能直接刪除。請先從分期明細撤銷繳款，或保留原消費紀錄。',
      );
    }
    await _installmentRepository.cancelPlan(plan.id);
  }
}

bool _isExecutedInstallmentScheduleItem(InstallmentScheduleItemRecord item) {
  return item.status == InstallmentScheduleItemStatus.paid ||
      (item.generatedTransactionId != null &&
          item.generatedTransactionId!.trim().isNotEmpty);
}
