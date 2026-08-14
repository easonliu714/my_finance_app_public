import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_repository.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_service.dart';
import 'package:my_finance_app/features/transaction/transaction_providers.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_store.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  test('previewLinkedInstallmentSourceDeletion returns cancelWithSource for unexecuted source plan', () async {
    final store = _FakeTransactionStore(records: [_sourceExpense('tx-source')]);
    final repository = InMemoryCreditCardInstallmentRepository();
    final controller = TransactionLedgerController(store, installmentRepository: repository);
    await controller.load();
    await _createPlan(repository, sourceTransactionId: 'tx-source');

    final preview = await controller.previewLinkedInstallmentSourceDeletion('tx-source');

    expect(preview.action, LinkedInstallmentSourceDeleteAction.cancelWithSource);
    expect(preview.canDeleteWithPlanCancel, isTrue);
    expect(preview.scheduleCount, 3);
    expect(preview.executedScheduleCount, 0);
  });

  test('delete source transaction cancels unexecuted installment plan and deletes source record', () async {
    final store = _FakeTransactionStore(records: [_sourceExpense('tx-source')]);
    final repository = InMemoryCreditCardInstallmentRepository();
    final controller = TransactionLedgerController(store, installmentRepository: repository);
    await controller.load();
    await _createPlan(repository, sourceTransactionId: 'tx-source');

    await controller.delete('tx-source');

    expect(store.records, isEmpty);
    expect(await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.active), isEmpty);
    final cancelled = await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.cancelled);
    expect(cancelled.map((item) => item.id), ['plan-tx-source']);
  });

  test('delete source transaction is blocked when linked installment has generated payment', () async {
    final store = _FakeTransactionStore(records: [_sourceExpense('tx-source')]);
    final repository = InMemoryCreditCardInstallmentRepository();
    final controller = TransactionLedgerController(store, installmentRepository: repository);
    await controller.load();
    await _createPlan(repository, sourceTransactionId: 'tx-source');
    await repository.markScheduleItemPaid(
      planId: 'plan-tx-source',
      scheduleItemId: 'plan-tx-source-1',
      generatedTransactionId: 'generated-payment-1',
    );

    final preview = await controller.previewLinkedInstallmentSourceDeletion('tx-source');

    expect(preview.action, LinkedInstallmentSourceDeleteAction.blockedExecuted);
    expect(preview.isBlocked, isTrue);
    expect(preview.executedScheduleCount, 1);
    expect(
      () => controller.delete('tx-source'),
      throwsA(isA<TransactionLinkedInstallmentDeleteBlocked>()),
    );
    expect(store.records.map((item) => item.id), ['tx-source']);
    expect(await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.active), hasLength(1));
  });
}

Future<void> _createPlan(InMemoryCreditCardInstallmentRepository repository, {required String sourceTransactionId}) async {
  final input = CreditCardInstallmentPlanInput(
    id: 'plan-$sourceTransactionId',
    scenario: CreditCardInstallmentScenario.purchaseTime,
    cardId: 'card-1',
    cardName: '信用卡A',
    currency: CurrencyCode.twd,
    principal: 12000,
    termCount: 3,
    firstStatementDate: DateTime(2026, 7, 5),
    sourceTransactionId: sourceTransactionId,
  );
  await repository.createPlan(input: input, schedule: buildCreditCardInstallmentSchedule(input));
}

TransactionRecord _sourceExpense(String id) {
  return TransactionRecord(
    id: id,
    type: TransactionType.expense,
    amount: 12000,
    category: '日常',
    occurredAt: DateTime(2026, 6, 1),
    accountName: '信用卡A',
    memberName: '自己',
    merchantName: '商家',
    tagName: '日常',
    note: '',
  );
}

class _FakeTransactionStore implements TransactionStore {
  _FakeTransactionStore({required List<TransactionRecord> records}) : records = [...records];

  final List<TransactionRecord> records;

  @override
  Future<void> insert(TransactionRecord record) async {
    records.add(record);
  }

  @override
  Future<void> update(TransactionRecord record) async {
    final index = records.indexWhere((item) => item.id == record.id);
    if (index >= 0) records[index] = record;
  }

  @override
  Future<void> deleteById(String id) async {
    records.removeWhere((item) => item.id == id);
  }

  @override
  Future<void> deleteByRepaymentGroupId(String repaymentGroupId) async {
    records.removeWhere((item) => item.repaymentGroupId == repaymentGroupId);
  }

  @override
  Future<void> deleteLoanRepaymentCluster(TransactionRecord record) async {
    if (record.repaymentGroupId == null) return;
    await deleteByRepaymentGroupId(record.repaymentGroupId!);
  }

  @override
  Future<List<TransactionRecord>> listRecent({int limit = 50}) async {
    return records.take(limit).toList(growable: false);
  }

  @override
  Future<double> monthlyIncome(DateTime month) async => 0;

  @override
  Future<double> monthlyExpense(DateTime month) async => records.fold<double>(0, (sum, item) => item.type == TransactionType.expense ? sum + item.amount : sum);
}
