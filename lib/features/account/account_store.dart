import '../plan/credit_card_bank_rule_profile.dart';
import '../plan/credit_card_statement_event.dart';
import '../transaction/transaction_record.dart';
import 'account_event_record.dart';
import 'account_record.dart';

abstract class AccountStore {
  Future<List<AccountRecord>> listAccounts({bool includeArchived = false});
  Future<void> upsertAccount(AccountRecord account);
  Future<void> archiveAccount(String id);
  Future<List<AccountEventRecord>> listAccountEvents(String accountName);
  Future<List<TransactionRecord>> listAccountTransactions(String accountName);
  Future<void> upsertAccountEvent(AccountEventRecord event);
  Future<void> deleteAccountEvent(String id);

  Future<List<CreditCardStatementEvent>> listCreditCardStatementEvents(
    String cardId,
  ) {
    throw UnimplementedError(
      'Credit card statement events are only supported by stores that opt in.',
    );
  }

  Future<void> upsertCreditCardStatementEvent(
    CreditCardStatementEvent event,
  ) {
    throw UnimplementedError(
      'Credit card statement events are only supported by stores that opt in.',
    );
  }

  Future<void> deleteCreditCardStatementEvent(String id) {
    throw UnimplementedError(
      'Credit card statement events are only supported by stores that opt in.',
    );
  }

  Future<List<CreditCardBankRuleProfile>> listCreditCardBankRuleProfiles() {
    throw UnimplementedError(
      'Credit card bank rule profiles are only supported by stores that opt in.',
    );
  }

  Future<void> upsertCreditCardBankRuleProfile(
    CreditCardBankRuleProfile profile,
  ) {
    throw UnimplementedError(
      'Credit card bank rule profiles are only supported by stores that opt in.',
    );
  }

  Future<void> deleteCreditCardBankRuleProfile(String id) {
    throw UnimplementedError(
      'Credit card bank rule profiles are only supported by stores that opt in.',
    );
  }

  Future<String?> getCreditCardBankRuleProfileId(String cardId) {
    throw UnimplementedError(
      'Credit card bank rule assignments are only supported by stores that opt in.',
    );
  }

  Future<void> setCreditCardBankRuleProfileId(
    String cardId,
    String? profileId,
  ) {
    throw UnimplementedError(
      'Credit card bank rule assignments are only supported by stores that opt in.',
    );
  }
}
