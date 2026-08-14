import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/debit_card_account_profile.dart';

void main() {
  AccountRecord account({
    required String id,
    required AccountType type,
    CurrencyCode currency = CurrencyCode.twd,
    bool isArchived = false,
  }) {
    return AccountRecord(
      id: id,
      name: '測試帳戶',
      type: type,
      initialBalance: 1000,
      sortOrder: 0,
      currency: currency,
      isArchived: isArchived,
    );
  }

  group('DebitCardAccountProfile.link', () {
    test('creates a normalized link to an active bank account', () {
      final profile = DebitCardAccountProfile.link(
        debitCardAccountId: ' debit-card-1 ',
        linkedBankAccount: account(
          id: ' bank-1 ',
          type: AccountType.bank,
        ),
        debitCardCurrency: CurrencyCode.twd,
      );

      expect(profile.debitCardAccountId, 'debit-card-1');
      expect(profile.linkedBankAccountId, 'bank-1');
      expect(profile.currency, CurrencyCode.twd);
      expect(profile.settlementBusinessDays, 2);
      expect(profile.isEnabled, isTrue);
    });

    test('rejects an empty linked bank identity', () {
      expect(
        () => DebitCardAccountProfile.link(
          debitCardAccountId: 'debit-card-1',
          linkedBankAccount: account(
            id: '   ',
            type: AccountType.bank,
          ),
          debitCardCurrency: CurrencyCode.twd,
        ),
        throwsA(
          isA<DebitCardAccountLinkException>().having(
            (error) => error.code,
            'code',
            DebitCardAccountLinkErrorCode.emptyLinkedBankAccountId,
          ),
        ),
      );
    });

    test('rejects the same debit-card and bank identity', () {
      expect(
        () => DebitCardAccountProfile.link(
          debitCardAccountId: 'same-id',
          linkedBankAccount: account(
            id: 'same-id',
            type: AccountType.bank,
          ),
          debitCardCurrency: CurrencyCode.twd,
        ),
        throwsA(
          isA<DebitCardAccountLinkException>().having(
            (error) => error.code,
            'code',
            DebitCardAccountLinkErrorCode.sameAccountIdentity,
          ),
        ),
      );
    });

    test('rejects a linked account that is not a bank', () {
      expect(
        () => DebitCardAccountProfile.link(
          debitCardAccountId: 'debit-card-1',
          linkedBankAccount: account(
            id: 'cash-1',
            type: AccountType.cash,
          ),
          debitCardCurrency: CurrencyCode.twd,
        ),
        throwsA(
          isA<DebitCardAccountLinkException>().having(
            (error) => error.code,
            'code',
            DebitCardAccountLinkErrorCode.linkedAccountMustBeBank,
          ),
        ),
      );
    });

    test('rejects an archived bank account', () {
      expect(
        () => DebitCardAccountProfile.link(
          debitCardAccountId: 'debit-card-1',
          linkedBankAccount: account(
            id: 'bank-archived',
            type: AccountType.bank,
            isArchived: true,
          ),
          debitCardCurrency: CurrencyCode.twd,
        ),
        throwsA(
          isA<DebitCardAccountLinkException>().having(
            (error) => error.code,
            'code',
            DebitCardAccountLinkErrorCode.linkedAccountArchived,
          ),
        ),
      );
    });

    test('rejects a currency mismatch', () {
      expect(
        () => DebitCardAccountProfile.link(
          debitCardAccountId: 'debit-card-usd',
          linkedBankAccount: account(
            id: 'bank-twd',
            type: AccountType.bank,
          ),
          debitCardCurrency: CurrencyCode.usd,
        ),
        throwsA(
          isA<DebitCardAccountLinkException>().having(
            (error) => error.code,
            'code',
            DebitCardAccountLinkErrorCode.currencyMismatch,
          ),
        ),
      );
    });

    test('rejects negative settlement business days', () {
      expect(
        () => DebitCardAccountProfile.link(
          debitCardAccountId: 'debit-card-1',
          linkedBankAccount: account(
            id: 'bank-1',
            type: AccountType.bank,
          ),
          debitCardCurrency: CurrencyCode.twd,
          settlementBusinessDays: -1,
        ),
        throwsA(
          isA<DebitCardAccountLinkException>().having(
            (error) => error.code,
            'code',
            DebitCardAccountLinkErrorCode.invalidSettlementBusinessDays,
          ),
        ),
      );
    });
  });

  test('posting policy records purchase once and settles by transfer', () {
    const policy = DebitCardPostingPolicy();

    expect(policy.purchasePosting, DebitCardPostingKind.purchaseExpense);
    expect(
      policy.confirmedSettlementPosting,
      DebitCardPostingKind.settlementTransfer,
    );
    expect(policy.cancellationPosting, DebitCardPostingKind.cancellationReversal);
    expect(policy.purchaseMutatesLinkedBankLedger, isFalse);
    expect(policy.confirmedSettlementMutatesLinkedBankLedger, isTrue);
    expect(policy.confirmedSettlementCreatesAdditionalExpense, isFalse);
  });
}
