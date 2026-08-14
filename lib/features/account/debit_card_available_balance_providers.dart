import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../transaction/debit_card_available_balance_read_service.dart';
import '../transaction/transaction_providers.dart';
import 'account_providers.dart';
import 'account_record.dart';
import 'account_repository.dart';
import 'debit_card_available_balance_presentation.dart';
import 'debit_card_available_balance_read_source.dart';

final debitCardAvailableBalanceReadSourceProvider =
    Provider<DebitCardAvailableBalanceReadSource>((ref) {
  return AccountRepositoryDebitCardAvailableBalanceReadSource(
    AccountRepository.instance,
  );
});

final debitCardAvailableBalanceReadServiceProvider =
    Provider<DebitCardAvailableBalanceReadService>((ref) {
  final source = ref.watch(debitCardAvailableBalanceReadSourceProvider);
  return DebitCardAvailableBalanceReadService(source: source);
});

final debitCardAvailableBalancePresentationServiceProvider =
    Provider<DebitCardAvailableBalancePresentationService>((ref) {
  final source = ref.watch(debitCardAvailableBalanceReadSourceProvider);
  final readService = ref.watch(debitCardAvailableBalanceReadServiceProvider);
  return DebitCardAvailableBalancePresentationService(
    source: source,
    readService: readService,
  );
});

final accountAvailableBalancePresentationProvider = FutureProvider.autoDispose
    .family<AccountAvailableBalancePresentation?, AccountRecord>(
  (ref, account) async {
    ref.watch(accountListProvider);
    ref.watch(transactionLedgerProvider);
    final service =
        ref.watch(debitCardAvailableBalancePresentationServiceProvider);
    return service.load(account);
  },
);
