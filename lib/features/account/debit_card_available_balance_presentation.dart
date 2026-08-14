import '../transaction/debit_card_available_balance.dart';
import '../transaction/debit_card_available_balance_read_service.dart';
import 'account_record.dart';
import 'debit_card_available_balance_read_source.dart';

class AccountAvailableBalancePresentation {
  const AccountAvailableBalancePresentation({
    required this.viewedAccount,
    required this.linkedBankAccount,
    required this.linkedDebitCardAccounts,
    required this.snapshot,
  });

  final AccountRecord viewedAccount;
  final AccountRecord linkedBankAccount;
  final List<AccountRecord> linkedDebitCardAccounts;
  final DebitCardAvailableBalanceSnapshot snapshot;

  bool get isDebitCardContext => viewedAccount.type == AccountType.debitCard;
  bool get isLinkedBankContext => viewedAccount.type == AccountType.bank;

  String get relationshipLabel {
    if (isDebitCardContext) {
      return '扣款帳戶：${linkedBankAccount.displayName}';
    }
    final names = linkedDebitCardAccounts
        .map((account) => account.displayName)
        .join('、');
    return '共用此帳戶的簽帳金融卡：$names';
  }
}

class DebitCardAvailableBalancePresentationService {
  const DebitCardAvailableBalancePresentationService({
    required this.source,
    required this.readService,
  });

  final DebitCardAvailableBalanceReadSource source;
  final DebitCardAvailableBalanceReadService readService;

  Future<AccountAvailableBalancePresentation?> load(
    AccountRecord viewedAccount,
  ) async {
    if (viewedAccount.type != AccountType.debitCard &&
        viewedAccount.type != AccountType.bank) {
      return null;
    }

    final accounts = await source.listAccounts(includeArchived: true);
    final canonicalViewedAccount =
        _findAccount(accounts, viewedAccount.id) ?? viewedAccount;

    if (canonicalViewedAccount.type == AccountType.debitCard) {
      final profile = await source.getDebitCardProfile(
        canonicalViewedAccount.id,
      );
      if (profile == null) {
        await readService.load(canonicalViewedAccount.id);
        return null;
      }
      final linkedBank = _findAccount(
        accounts,
        profile.linkedBankAccountId,
      );
      if (linkedBank == null) {
        await readService.load(canonicalViewedAccount.id);
        return null;
      }
      final snapshot = await readService.load(canonicalViewedAccount.id);
      return AccountAvailableBalancePresentation(
        viewedAccount: canonicalViewedAccount,
        linkedBankAccount: linkedBank,
        linkedDebitCardAccounts: <AccountRecord>[canonicalViewedAccount],
        snapshot: snapshot,
      );
    }

    final linkedDebitCards = <AccountRecord>[];
    for (final account in accounts) {
      if (account.type != AccountType.debitCard || account.isArchived) {
        continue;
      }
      final profile = await source.getDebitCardProfile(account.id);
      if (profile == null ||
          !profile.isEnabled ||
          profile.linkedBankAccountId != canonicalViewedAccount.id) {
        continue;
      }
      linkedDebitCards.add(account);
    }
    linkedDebitCards.sort(
      (left, right) => left.displayName.compareTo(right.displayName),
    );

    if (linkedDebitCards.isEmpty) return null;

    final snapshot = await readService.load(linkedDebitCards.first.id);
    return AccountAvailableBalancePresentation(
      viewedAccount: canonicalViewedAccount,
      linkedBankAccount: canonicalViewedAccount,
      linkedDebitCardAccounts: List<AccountRecord>.unmodifiable(
        linkedDebitCards,
      ),
      snapshot: snapshot,
    );
  }

  AccountRecord? _findAccount(
    Iterable<AccountRecord> accounts,
    String id,
  ) {
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }
}
