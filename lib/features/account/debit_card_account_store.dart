import 'account_record.dart';
import 'debit_card_account_profile.dart';

abstract interface class DebitCardAccountStore {
  Future<DebitCardAccountProfile?> getDebitCardProfile(String accountId);

  Future<void> upsertDebitCardAccount(
    AccountRecord account,
    DebitCardAccountProfile profile,
  );
}
