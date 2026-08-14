import '../account/account_record.dart';
import '../account/debit_card_account_profile.dart';
import 'debit_card_settlement.dart';

enum DebitCardAvailableBalanceContextErrorCode {
  profileDisabled,
  debitCardIdentityMismatch,
  debitCardAccountTypeMismatch,
  debitCardAccountArchived,
  linkedBankIdentityMismatch,
  linkedAccountMustBeBank,
  linkedBankAccountArchived,
  currencyMismatch,
  invalidLedgerBalance,
}

class DebitCardAvailableBalanceContextException implements Exception {
  const DebitCardAvailableBalanceContextException(this.code, this.message);

  final DebitCardAvailableBalanceContextErrorCode code;
  final String message;

  @override
  String toString() =>
      'DebitCardAvailableBalanceContextException($code): $message';
}

class DebitCardAvailableBalanceSnapshot {
  const DebitCardAvailableBalanceSnapshot({
    required this.debitCardAccountId,
    required this.linkedBankAccountId,
    required this.currency,
    required this.ledgerBalance,
    required this.reservedPendingAmount,
    required this.availableBalance,
    required this.activeReservationCount,
  });

  final String debitCardAccountId;
  final String linkedBankAccountId;
  final CurrencyCode currency;
  final double ledgerBalance;
  final double reservedPendingAmount;
  final double availableBalance;
  final int activeReservationCount;

  bool get isOverReserved => availableBalance < 0;

  double get overReservedAmount => currency.roundAmount(
        isOverReserved ? -availableBalance : 0,
      );

  double get spendableAmount => currency.roundAmount(
        availableBalance > 0 ? availableBalance : 0,
      );

  bool canAuthorize(double requestedAmount) {
    if (!requestedAmount.isFinite || requestedAmount <= 0) return false;
    final normalized = currency.roundAmount(requestedAmount);
    return normalized > 0 && normalized <= availableBalance;
  }

  double shortfallFor(double requestedAmount) {
    if (!requestedAmount.isFinite || requestedAmount <= 0) {
      throw ArgumentError.value(
        requestedAmount,
        'requestedAmount',
        'Must be a finite positive value.',
      );
    }
    final normalized = currency.roundAmount(requestedAmount);
    if (normalized <= 0) {
      throw ArgumentError.value(
        requestedAmount,
        'requestedAmount',
        'Rounds to zero in ${currency.code}.',
      );
    }
    final shortfall = normalized - availableBalance;
    return currency.roundAmount(shortfall > 0 ? shortfall : 0);
  }
}

class DebitCardAvailableBalanceService {
  const DebitCardAvailableBalanceService({
    this.planner = const DebitCardSettlementPlanner(),
  });

  final DebitCardSettlementPlanner planner;

  DebitCardAvailableBalanceSnapshot buildSnapshot({
    required DebitCardAccountProfile profile,
    required AccountRecord debitCardAccount,
    required AccountRecord linkedBankAccount,
    required double currentBankLedgerBalance,
    required Iterable<DebitCardPendingSettlement> settlements,
  }) {
    _validateContext(
      profile: profile,
      debitCardAccount: debitCardAccount,
      linkedBankAccount: linkedBankAccount,
      currentBankLedgerBalance: currentBankLedgerBalance,
    );

    final settlementList = settlements.toList(growable: false);
    final currency = profile.currency;
    final ledgerBalance = currency.roundAmount(currentBankLedgerBalance);
    final reservedPendingAmount = planner.reservedAmount(
      settlements: settlementList,
      linkedBankAccountId: profile.linkedBankAccountId,
      currency: currency,
    );
    final availableBalance = planner.availableBalance(
      currentBankBalance: ledgerBalance,
      settlements: settlementList,
      linkedBankAccountId: profile.linkedBankAccountId,
      currency: currency,
    );
    final activeReservationCount = settlementList.where((item) {
      return item.reservesAvailableBalance &&
          item.linkedBankAccountId == profile.linkedBankAccountId &&
          item.currency == currency;
    }).length;

    return DebitCardAvailableBalanceSnapshot(
      debitCardAccountId: profile.debitCardAccountId,
      linkedBankAccountId: profile.linkedBankAccountId,
      currency: currency,
      ledgerBalance: ledgerBalance,
      reservedPendingAmount: reservedPendingAmount,
      availableBalance: availableBalance,
      activeReservationCount: activeReservationCount,
    );
  }

  void _validateContext({
    required DebitCardAccountProfile profile,
    required AccountRecord debitCardAccount,
    required AccountRecord linkedBankAccount,
    required double currentBankLedgerBalance,
  }) {
    if (!profile.isEnabled) {
      throw const DebitCardAvailableBalanceContextException(
        DebitCardAvailableBalanceContextErrorCode.profileDisabled,
        'Debit-card profile is disabled.',
      );
    }
    if (debitCardAccount.id != profile.debitCardAccountId) {
      throw const DebitCardAvailableBalanceContextException(
        DebitCardAvailableBalanceContextErrorCode.debitCardIdentityMismatch,
        'Debit-card account does not match the profile owner.',
      );
    }
    if (debitCardAccount.type != AccountType.debitCard) {
      throw const DebitCardAvailableBalanceContextException(
        DebitCardAvailableBalanceContextErrorCode
            .debitCardAccountTypeMismatch,
        'Profile owner must be a debit-card account.',
      );
    }
    if (debitCardAccount.isArchived) {
      throw const DebitCardAvailableBalanceContextException(
        DebitCardAvailableBalanceContextErrorCode.debitCardAccountArchived,
        'Archived debit-card accounts cannot authorize purchases.',
      );
    }
    if (linkedBankAccount.id != profile.linkedBankAccountId) {
      throw const DebitCardAvailableBalanceContextException(
        DebitCardAvailableBalanceContextErrorCode.linkedBankIdentityMismatch,
        'Linked bank account does not match the profile.',
      );
    }
    if (linkedBankAccount.type != AccountType.bank) {
      throw const DebitCardAvailableBalanceContextException(
        DebitCardAvailableBalanceContextErrorCode.linkedAccountMustBeBank,
        'Linked account must be a bank account.',
      );
    }
    if (linkedBankAccount.isArchived) {
      throw const DebitCardAvailableBalanceContextException(
        DebitCardAvailableBalanceContextErrorCode.linkedBankAccountArchived,
        'Archived bank accounts cannot provide available balance.',
      );
    }
    if (debitCardAccount.currency != profile.currency ||
        linkedBankAccount.currency != profile.currency) {
      throw const DebitCardAvailableBalanceContextException(
        DebitCardAvailableBalanceContextErrorCode.currencyMismatch,
        'Profile, debit-card, and linked-bank currencies must all match.',
      );
    }
    if (!currentBankLedgerBalance.isFinite) {
      throw const DebitCardAvailableBalanceContextException(
        DebitCardAvailableBalanceContextErrorCode.invalidLedgerBalance,
        'Bank ledger balance must be finite.',
      );
    }
  }
}
