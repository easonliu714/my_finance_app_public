import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/debit_card_account_profile.dart';
import 'package:my_finance_app/features/transaction/debit_card_available_balance.dart';
import 'package:my_finance_app/features/transaction/debit_card_settlement.dart';

void main() {
  const service = DebitCardAvailableBalanceService();
  final authorizedAt = DateTime.utc(2026, 7, 3, 10);

  AccountRecord debitCard({
    String id = 'debit-1',
    CurrencyCode currency = CurrencyCode.twd,
    bool archived = false,
  }) {
    return AccountRecord(
      id: id,
      name: 'Debit',
      type: AccountType.debitCard,
      initialBalance: 0,
      sortOrder: 10,
      currency: currency,
      isArchived: archived,
    );
  }

  AccountRecord bank({
    String id = 'bank-1',
    CurrencyCode currency = CurrencyCode.twd,
    bool archived = false,
    AccountType type = AccountType.bank,
  }) {
    return AccountRecord(
      id: id,
      name: 'Bank',
      type: type,
      initialBalance: 0,
      sortOrder: 20,
      currency: currency,
      isArchived: archived,
    );
  }

  DebitCardAccountProfile profile({
    String debitCardId = 'debit-1',
    AccountRecord? linkedBank,
    CurrencyCode currency = CurrencyCode.twd,
    bool enabled = true,
  }) {
    return DebitCardAccountProfile.link(
      debitCardAccountId: debitCardId,
      linkedBankAccount: linkedBank ?? bank(currency: currency),
      debitCardCurrency: currency,
      isEnabled: enabled,
    );
  }

  DebitCardPendingSettlement pending({
    required String id,
    required double amount,
    String debitCardId = 'debit-1',
    String bankId = 'bank-1',
    CurrencyCode currency = CurrencyCode.twd,
  }) {
    return DebitCardPendingSettlement.authorize(
      id: id,
      debitCardAccountId: debitCardId,
      linkedBankAccountId: bankId,
      transactionId: 'transaction-$id',
      amount: amount,
      currency: currency,
      authorizedAt: authorizedAt,
    );
  }

  test('aggregates matching pending reservations across debit cards', () {
    final activeOne = pending(id: 'active-1', amount: 300);
    final activeTwo = pending(
      id: 'active-2',
      amount: 200,
      debitCardId: 'debit-2',
    );
    final confirmed = pending(id: 'confirmed', amount: 100).confirm(
      authorizedAt.add(const Duration(days: 2)),
    );
    final otherBank = pending(
      id: 'other-bank',
      amount: 400,
      bankId: 'bank-2',
    );
    final otherCurrency = pending(
      id: 'other-currency',
      amount: 10,
      currency: CurrencyCode.usd,
    );

    final snapshot = service.buildSnapshot(
      profile: profile(),
      debitCardAccount: debitCard(),
      linkedBankAccount: bank(),
      currentBankLedgerBalance: 1000,
      settlements: [
        activeOne,
        activeTwo,
        confirmed,
        otherBank,
        otherCurrency,
      ],
    );

    expect(snapshot.ledgerBalance, 1000);
    expect(snapshot.reservedPendingAmount, 500);
    expect(snapshot.availableBalance, 500);
    expect(snapshot.activeReservationCount, 2);
    expect(snapshot.isOverReserved, isFalse);
  });

  test('uses currency rounding for ledger, reservations, and capacity', () {
    final usdBank = bank(currency: CurrencyCode.usd);
    final snapshot = service.buildSnapshot(
      profile: profile(
        linkedBank: usdBank,
        currency: CurrencyCode.usd,
      ),
      debitCardAccount: debitCard(currency: CurrencyCode.usd),
      linkedBankAccount: usdBank,
      currentBankLedgerBalance: 100.126,
      settlements: [
        pending(
          id: 'usd-pending',
          amount: 0.124,
          currency: CurrencyCode.usd,
        ),
      ],
    );

    expect(snapshot.ledgerBalance, 100.13);
    expect(snapshot.reservedPendingAmount, 0.12);
    expect(snapshot.availableBalance, 100.01);
    expect(snapshot.canAuthorize(100.006), isTrue);
    expect(snapshot.canAuthorize(100.016), isFalse);
  });

  test('preserves negative available balance for audit visibility', () {
    final snapshot = service.buildSnapshot(
      profile: profile(),
      debitCardAccount: debitCard(),
      linkedBankAccount: bank(),
      currentBankLedgerBalance: 100,
      settlements: [pending(id: 'over-reserved', amount: 120)],
    );

    expect(snapshot.availableBalance, -20);
    expect(snapshot.isOverReserved, isTrue);
    expect(snapshot.overReservedAmount, 20);
    expect(snapshot.spendableAmount, 0);
    expect(snapshot.canAuthorize(1), isFalse);
    expect(snapshot.shortfallFor(1), 21);
  });

  test('authorization helpers reject invalid or rounded-to-zero amounts', () {
    final snapshot = service.buildSnapshot(
      profile: profile(),
      debitCardAccount: debitCard(),
      linkedBankAccount: bank(),
      currentBankLedgerBalance: 500,
      settlements: const [],
    );

    expect(snapshot.canAuthorize(500), isTrue);
    expect(snapshot.canAuthorize(501), isFalse);
    expect(snapshot.canAuthorize(0.4), isFalse);
    expect(snapshot.canAuthorize(double.nan), isFalse);
    expect(snapshot.shortfallFor(501), 1);
    expect(snapshot.shortfallFor(499), 0);
    expect(() => snapshot.shortfallFor(0.4), throwsArgumentError);
  });

  test('disabled profile fails closed', () {
    expect(
      () => service.buildSnapshot(
        profile: profile(enabled: false),
        debitCardAccount: debitCard(),
        linkedBankAccount: bank(),
        currentBankLedgerBalance: 1000,
        settlements: const [],
      ),
      throwsA(
        isA<DebitCardAvailableBalanceContextException>().having(
          (error) => error.code,
          'code',
          DebitCardAvailableBalanceContextErrorCode.profileDisabled,
        ),
      ),
    );
  });

  test('archived linked bank account fails closed', () {
    final activeBank = bank();
    expect(
      () => service.buildSnapshot(
        profile: profile(linkedBank: activeBank),
        debitCardAccount: debitCard(),
        linkedBankAccount: activeBank.copyWith(isArchived: true),
        currentBankLedgerBalance: 1000,
        settlements: const [],
      ),
      throwsA(
        isA<DebitCardAvailableBalanceContextException>().having(
          (error) => error.code,
          'code',
          DebitCardAvailableBalanceContextErrorCode.linkedBankAccountArchived,
        ),
      ),
    );
  });

  test('identity and currency mismatches fail closed', () {
    final twdProfile = profile();

    expect(
      () => service.buildSnapshot(
        profile: twdProfile,
        debitCardAccount: debitCard(id: 'debit-other'),
        linkedBankAccount: bank(),
        currentBankLedgerBalance: 1000,
        settlements: const [],
      ),
      throwsA(
        isA<DebitCardAvailableBalanceContextException>().having(
          (error) => error.code,
          'code',
          DebitCardAvailableBalanceContextErrorCode.debitCardIdentityMismatch,
        ),
      ),
    );

    expect(
      () => service.buildSnapshot(
        profile: twdProfile,
        debitCardAccount: debitCard(),
        linkedBankAccount: bank(currency: CurrencyCode.usd),
        currentBankLedgerBalance: 1000,
        settlements: const [],
      ),
      throwsA(
        isA<DebitCardAvailableBalanceContextException>().having(
          (error) => error.code,
          'code',
          DebitCardAvailableBalanceContextErrorCode.currencyMismatch,
        ),
      ),
    );
  });

  test('non-finite ledger balance fails closed', () {
    expect(
      () => service.buildSnapshot(
        profile: profile(),
        debitCardAccount: debitCard(),
        linkedBankAccount: bank(),
        currentBankLedgerBalance: double.infinity,
        settlements: const [],
      ),
      throwsA(
        isA<DebitCardAvailableBalanceContextException>().having(
          (error) => error.code,
          'code',
          DebitCardAvailableBalanceContextErrorCode.invalidLedgerBalance,
        ),
      ),
    );
  });
}
