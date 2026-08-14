import '../transaction/debit_card_settlement.dart';
import '../transaction/transaction_record.dart';
import 'account_event_record.dart';
import 'account_record.dart';
import 'account_repository.dart';
import 'debit_card_account_profile.dart';
import 'debit_card_repository.dart';

abstract interface class DebitCardAvailableBalanceReadSource {
  Future<List<AccountRecord>> listAccounts({bool includeArchived = false});

  Future<DebitCardAccountProfile?> getDebitCardProfile(String accountId);

  Future<List<AccountEventRecord>> listAccountEvents(String accountName);

  Future<List<TransactionRecord>> listAccountTransactions(String accountName);

  Future<List<DebitCardPendingSettlement>> listPendingDebitCardSettlements();
}

class AccountRepositoryDebitCardAvailableBalanceReadSource
    implements DebitCardAvailableBalanceReadSource {
  const AccountRepositoryDebitCardAvailableBalanceReadSource(this.repository);

  final AccountRepository repository;

  @override
  Future<List<AccountRecord>> listAccounts({
    bool includeArchived = false,
  }) {
    return repository.listAccounts(includeArchived: includeArchived);
  }

  @override
  Future<DebitCardAccountProfile?> getDebitCardProfile(String accountId) {
    return repository.getDebitCardProfile(accountId);
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

  @override
  Future<List<DebitCardPendingSettlement>>
      listPendingDebitCardSettlements() async {
    final db = await repository.database;
    return DebitCardRepository(db).listSettlements(
      status: DebitCardSettlementStatus.pending,
    );
  }
}
