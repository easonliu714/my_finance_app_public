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
