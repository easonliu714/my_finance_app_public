import 'transaction_record.dart';

abstract class TransactionStore {
  Future<void> insert(TransactionRecord record);
  Future<void> update(TransactionRecord record);
  Future<void> deleteById(String id);
  Future<void> deleteByRepaymentGroupId(String repaymentGroupId);
  Future<void> deleteLoanRepaymentCluster(TransactionRecord record);
  Future<List<TransactionRecord>> listRecent({int limit = 50});

  /// Fail-closed duplicate guard for externally seeded formal-write identities.
  /// Implementations may override with an indexed lookup. The default keeps
  /// existing test/fake stores source-compatible while still enforcing the
  /// invoice handoff idempotency boundary before a new formal Save.
  Future<bool> existsById(String id) async {
    final normalized = id.trim();
    if (normalized.isEmpty) return false;
    final records = await listRecent(limit: 5000);
    return records.any((record) => record.id == normalized);
  }

  Future<double> monthlyIncome(DateTime month);
  Future<double> monthlyExpense(DateTime month);
}
