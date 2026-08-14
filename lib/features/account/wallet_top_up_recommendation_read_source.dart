import '../transaction/transaction_record.dart';
import 'account_event_record.dart';
import 'account_record.dart';
import 'account_repository.dart';

abstract interface class WalletTopUpRecommendationReadSource {
  Future<List<AccountRecord>> listAccounts({bool includeArchived = false});

  Future<List<AccountEventRecord>> listAccountEvents(String accountName);

  Future<List<TransactionRecord>> listAccountTransactions(String accountName);
}

class AccountRepositoryWalletTopUpRecommendationReadSource
    implements WalletTopUpRecommendationReadSource {
  const AccountRepositoryWalletTopUpRecommendationReadSource(this.repository);

  final AccountRepository repository;

  @override
  Future<List<AccountRecord>> listAccounts({
    bool includeArchived = false,
  }) {
    return repository.listAccounts(includeArchived: includeArchived);
  }

  @override
  Future<List<AccountEventRecord>> listAccountEvents(String accountName) {
    return repository.listAccountEvents(accountName);
  }

  @override
  Future<List<TransactionRecord>> listAccountTransactions(
    String accountName,
  ) {
    return repository.listAccountTransactions(accountName);
  }
}
