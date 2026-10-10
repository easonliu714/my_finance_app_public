import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_finance_app/features/invoice/invoice_award_payout_bookkeeping_contract.dart';
import 'package:my_finance_app/features/invoice/invoice_award_remittance_receipt_evidence.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  InvoiceAwardPayoutBookkeepingProposal candidate({
    String account='bank-1',
    String sha='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  }) => InvoiceAwardPayoutBookkeepingProposal(
        invoiceIdentity: 'candidate-one',
        awardPeriodId: '115-05-06',
        prizeTier: 'cloud-500',
        grossAmount: 500,
        localAccountId: account,
        externalRemittanceEligibleAt: DateTime.utc(2026, 8, 5, 16),
        officialDatasetFingerprint: sha,
        parserRuleVersion: 'test-v1',
      );

  test('manual observed receipt is idempotent, persists but cannot post', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = InvoiceAwardRemittanceReceiptRepository(prefs);
    final proposal = candidate();
    expect(repo.readForProposal(proposal), isNull);
    final initial = await repo.confirmObservedCredit(
      proposal: proposal,
      receivedAtUtc: DateTime.utc(2026, 10, 7),
      confirmedAtUtc: DateTime.utc(2026, 10, 8),
    );
    final second = await repo.confirmObservedCredit(
      proposal: proposal,
      receivedAtUtc: DateTime.utc(2026, 10, 8),
      confirmedAtUtc: DateTime.utc(2026, 10, 8),
    );
    expect(initial.receivedAtUtc, second.receivedAtUtc);
    expect(repo.loadAll(), hasLength(1));
    expect(repo.readForProposal(proposal)?.grossAmount, 500);
    final state = InvoiceAwardRemittanceCreditReadiness(
      proposal: proposal, observation: initial,
    );
    expect(state.isUserObservedOnly, isTrue);
    expect(state.isExternallyVerifiedBankCredit, isFalse);
    expect(state.canAutomaticallyPostFormalIncome, isFalse);
  });

  test('source or destination change invalidates old user observation', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = InvoiceAwardRemittanceReceiptRepository(prefs);
    await repo.confirmObservedCredit(
      proposal: candidate(),
      receivedAtUtc: DateTime.utc(2026, 10, 7),
      confirmedAtUtc: DateTime.utc(2026, 10, 8),
    );
    expect(repo.readForProposal(candidate(account:'bank-2')), isNull);
    expect(repo.readForProposal(candidate(
      sha:'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')), isNull);
  });

  test('dates fail closed and revoke clears receipt', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = InvoiceAwardRemittanceReceiptRepository(prefs);
    final proposal = candidate();
    await expectLater(
      repo.confirmObservedCredit(
        proposal: proposal,
        receivedAtUtc: DateTime.utc(2026, 8, 5),
        confirmedAtUtc: DateTime.utc(2026, 10, 8),
      ),
      throwsStateError,
    );
    await repo.confirmObservedCredit(
      proposal: proposal,
      receivedAtUtc: DateTime.utc(2026, 10, 7),
      confirmedAtUtc: DateTime.utc(2026, 10, 8),
    );
    await repo.revokeForProposal(proposal);
    expect(repo.readForProposal(proposal), isNull);
  });
}
