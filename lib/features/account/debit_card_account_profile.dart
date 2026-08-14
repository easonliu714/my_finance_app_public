import 'account_record.dart';

enum DebitCardAccountLinkErrorCode {
  emptyDebitCardAccountId,
  emptyLinkedBankAccountId,
  sameAccountIdentity,
  linkedAccountMustBeBank,
  linkedAccountArchived,
  currencyMismatch,
  invalidSettlementBusinessDays,
}

class DebitCardAccountLinkException implements Exception {
  const DebitCardAccountLinkException(this.code, this.message);

  final DebitCardAccountLinkErrorCode code;
  final String message;

  @override
  String toString() => 'DebitCardAccountLinkException($code): $message';
}

class DebitCardAccountProfile {
  const DebitCardAccountProfile._({
    required this.debitCardAccountId,
    required this.linkedBankAccountId,
    required this.currency,
    required this.settlementBusinessDays,
    required this.isEnabled,
  });

  factory DebitCardAccountProfile.link({
    required String debitCardAccountId,
    required AccountRecord linkedBankAccount,
    required CurrencyCode debitCardCurrency,
    int settlementBusinessDays = 2,
    bool isEnabled = true,
  }) {
    final profile = DebitCardAccountProfile._validated(
      debitCardAccountId: debitCardAccountId,
      linkedBankAccountId: linkedBankAccount.id,
      currency: debitCardCurrency,
      settlementBusinessDays: settlementBusinessDays,
      isEnabled: isEnabled,
    );

    if (linkedBankAccount.type != AccountType.bank) {
      throw const DebitCardAccountLinkException(
        DebitCardAccountLinkErrorCode.linkedAccountMustBeBank,
        'A debit card can link only to a bank account.',
      );
    }
    if (linkedBankAccount.isArchived) {
      throw const DebitCardAccountLinkException(
        DebitCardAccountLinkErrorCode.linkedAccountArchived,
        'An archived bank account cannot be linked to a debit card.',
      );
    }
    if (linkedBankAccount.currency != debitCardCurrency) {
      throw DebitCardAccountLinkException(
        DebitCardAccountLinkErrorCode.currencyMismatch,
        'Debit-card currency ${debitCardCurrency.code} must match linked '
        'bank-account currency ${linkedBankAccount.currency.code}.',
      );
    }
    return profile;
  }

  factory DebitCardAccountProfile.fromMap(Map<String, Object?> map) {
    return DebitCardAccountProfile._validated(
      debitCardAccountId: map['debit_card_account_id'] as String,
      linkedBankAccountId: map['linked_bank_account_id'] as String,
      currency: currencyFromCode(map['currency_code'] as String?),
      settlementBusinessDays:
          (map['settlement_business_days'] as num?)?.toInt() ?? 2,
      isEnabled: (map['is_enabled'] as num?)?.toInt() != 0,
    );
  }

  factory DebitCardAccountProfile._validated({
    required String debitCardAccountId,
    required String linkedBankAccountId,
    required CurrencyCode currency,
    required int settlementBusinessDays,
    required bool isEnabled,
  }) {
    final normalizedDebitCardId = debitCardAccountId.trim();
    final normalizedBankId = linkedBankAccountId.trim();

    if (normalizedDebitCardId.isEmpty) {
      throw const DebitCardAccountLinkException(
        DebitCardAccountLinkErrorCode.emptyDebitCardAccountId,
        'Debit-card account identity must not be empty.',
      );
    }
    if (normalizedBankId.isEmpty) {
      throw const DebitCardAccountLinkException(
        DebitCardAccountLinkErrorCode.emptyLinkedBankAccountId,
        'Linked bank-account identity must not be empty.',
      );
    }
    if (normalizedDebitCardId == normalizedBankId) {
      throw const DebitCardAccountLinkException(
        DebitCardAccountLinkErrorCode.sameAccountIdentity,
        'Debit-card and linked bank-account identities must differ.',
      );
    }
    if (settlementBusinessDays < 0) {
      throw const DebitCardAccountLinkException(
        DebitCardAccountLinkErrorCode.invalidSettlementBusinessDays,
        'Settlement business days must not be negative.',
      );
    }

    return DebitCardAccountProfile._(
      debitCardAccountId: normalizedDebitCardId,
      linkedBankAccountId: normalizedBankId,
      currency: currency,
      settlementBusinessDays: settlementBusinessDays,
      isEnabled: isEnabled,
    );
  }

  final String debitCardAccountId;
  final String linkedBankAccountId;
  final CurrencyCode currency;
  final int settlementBusinessDays;
  final bool isEnabled;

  Map<String, Object?> toMap() => <String, Object?>{
        'debit_card_account_id': debitCardAccountId,
        'linked_bank_account_id': linkedBankAccountId,
        'currency_code': currency.code,
        'settlement_business_days': settlementBusinessDays,
        'is_enabled': isEnabled ? 1 : 0,
      };
}

enum DebitCardPostingKind {
  purchaseExpense,
  settlementTransfer,
  cancellationReversal,
}

class DebitCardPostingPolicy {
  const DebitCardPostingPolicy();

  DebitCardPostingKind get purchasePosting =>
      DebitCardPostingKind.purchaseExpense;

  DebitCardPostingKind get confirmedSettlementPosting =>
      DebitCardPostingKind.settlementTransfer;

  DebitCardPostingKind get cancellationPosting =>
      DebitCardPostingKind.cancellationReversal;

  bool get purchaseMutatesLinkedBankLedger => false;

  bool get confirmedSettlementMutatesLinkedBankLedger => true;

  bool get confirmedSettlementCreatesAdditionalExpense => false;
}
