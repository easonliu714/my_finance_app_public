import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/transaction/debit_card_settlement.dart';

void main() {
  const planner = DebitCardSettlementPlanner();
  final authorizedAt = DateTime.utc(2026, 6, 29, 10);

  DebitCardPendingSettlement pending({
    required String id,
    required double amount,
  }) {
    return DebitCardPendingSettlement.authorize(
      id: id,
      debitCardAccountId: 'debit-card-1',
      linkedBankAccountId: 'bank-1',
      transactionId: 'transaction-$id',
      amount: amount,
      currency: CurrencyCode.twd,
      authorizedAt: authorizedAt,
    );
  }

  test('default settlement date is two business days later', () {
    final settlement = planner.authorize(
      id: 'settlement-1',
      debitCardAccountId: 'debit-card-1',
      linkedBankAccountId: 'bank-1',
      transactionId: 'transaction-1',
      amount: 600,
      currency: CurrencyCode.twd,
      authorizedAt: DateTime.utc(2026, 7, 3, 14),
      currentBankBalance: 1000,
    );

    expect(settlement.status, DebitCardSettlementStatus.pending);
    expect(
      settlement.expectedSettlementDate,
      DateTime.utc(2026, 7, 7, 14),
    );
  });

  test('active pending authorization reduces available balance', () {
    final active = pending(id: 'pending-1', amount: 300);

    final available = planner.availableBalance(
      currentBankBalance: 1000,
      settlements: [active],
      linkedBankAccountId: 'bank-1',
      currency: CurrencyCode.twd,
    );

    expect(available, 700);
  });

  test('authorization above available balance is blocked', () {
    final existing = pending(id: 'existing-1', amount: 700);

    expect(
      () => planner.authorize(
        id: 'settlement-2',
        debitCardAccountId: 'debit-card-1',
        linkedBankAccountId: 'bank-1',
        transactionId: 'transaction-2',
        amount: 301,
        currency: CurrencyCode.twd,
        authorizedAt: authorizedAt,
        currentBankBalance: 1000,
        existingSettlements: [existing],
      ),
      throwsA(
        isA<DebitCardAuthorizationException>().having(
          (error) => error.code,
          'code',
          DebitCardAuthorizationErrorCode.insufficientAvailableBalance,
        ),
      ),
    );
  });

  test('confirmed settlement is terminal and releases reservation', () {
    final confirmedAt = authorizedAt.add(const Duration(days: 2));
    final confirmed = pending(
      id: 'state-1',
      amount: 100,
    ).confirm(confirmedAt);

    expect(confirmed.status, DebitCardSettlementStatus.confirmed);
    expect(confirmed.terminalAt, confirmedAt);
    expect(confirmed.reservesAvailableBalance, isFalse);
    expect(
      () => confirmed.cancel(authorizedAt.add(const Duration(days: 3))),
      throwsStateError,
    );
  });
}
