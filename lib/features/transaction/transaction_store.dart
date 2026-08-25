import 'transaction_record.dart';

abstract class TransactionStore {
  Future<void> insert(TransactionRecord record);
  Future<void> update(TransactionRecord record);
  Future<void> deleteById(String id);
  Future<void> deleteByRepaymentGroupId(String repaymentGroupId);
  Future<void> deleteLoanRepaymentCluster(TransactionRecord record);
  Future<List<TransactionRecord>> listRecent({int limit = 50});
  Future<double> monthlyIncome(DateTime month);
  Future<double> monthlyExpense(DateTime month);
}

extension TransactionStoreIdentityLookup on TransactionStore {
  /// Fail-closed duplicate guard for externally seeded formal-write identities.
  /// Kept as an extension so existing store implementations and test fakes do
  /// not gain a new required interface member.
  Future<bool> existsById(String id) async {
    final normalized = id.trim();
    if (normalized.isEmpty) return false;
    final records = await listRecent(limit: 5000);
    return records.any((record) => record.id == normalized);
  }
}
