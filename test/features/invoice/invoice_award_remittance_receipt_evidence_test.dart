import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_finance_app/features/invoice/invoice_award_payout_bookkeeping_contract.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud500_production_policy.dart';
import 'package:my_finance_app/features/invoice/invoice_award_remittance_receipt_evidence.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  InvoiceAwardPayoutBookkeepingProposal candidate({
    String account='bank-1',
    String sha='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    String tier='general-sixth',
    int amount=200,
  }) => InvoiceAwardPayoutBookkeepingProposal(
        invoiceIdentity: 'candidate-one',
        awardPeriodId: '115-05-06',
        prizeTier: tier,
        grossAmount: amount,
        localAccountId: account,
        externalRemittanceEligibleAt: DateTime.utc(2026, 8, 5, 16),
        officialDatasetFingerprint: sha,
        parserRuleVersion: 'test-v1',
      );


  test('Owner C blocks new 500 observations before preference writes while preserving old audit', () async {
    final legacy = candidate(tier: 'cloud-500', amount: 500);
    final historical = InvoiceAwardRemittanceReceiptEvidence(
      proposalKey: legacy.idempotencyKey,
      awardPeriodId: legacy.awardPeriodId,
      localAccountId: legacy.localAccountId,
      prizeTier: legacy.prizeTier,
      grossAmount: legacy.grossAmount,
      officialFingerprint: legacy.officialDatasetFingerprint,
      receivedAtUtc: DateTime.utc(2026, 10, 7),
      confirmedAtUtc: DateTime.utc(2026, 10, 8),
    );
    final originalBytes = jsonEncode(<Object>[historical.toJson()]);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'issue13_remittance_observations_v1': originalBytes,
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = InvoiceAwardRemittanceReceiptRepository(prefs);
    expect(repo.readForProposal(legacy)?.grossAmount, 500);

    // A repeat of an existing 500 receipt must not silently be accepted as
    // fresh release authorization; a new account cannot create one either.
    for (final blocked in <InvoiceAwardPayoutBookkeepingProposal>[
      legacy,
      candidate(tier: 'cloud-500', amount: 500, account: 'bank-2'),
    ]) {
      await expectLater(
        repo.confirmObservedCredit(
          proposal: blocked,
          receivedAtUtc: DateTime.utc(2026, 10, 9),
          confirmedAtUtc: DateTime.utc(2026, 10, 9),
        ),
        throwsA(isA<StateError>().having(
          (error) => error.toString(),
          'reason',
          contains(Cloud500ProductionPolicy.deferredCode),
        )),
      );
    }
    expect(prefs.getString('issue13_remittance_observations_v1'), originalBytes);
    expect(repo.loadAll(), hasLength(1));
    expect(repo.readForProposal(legacy)?.grossAmount, 500);
  });

  test('manual observed general receipt is idempotent, persists but cannot post', () async {
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
    expect(repo.readForProposal(proposal)?.grossAmount, 200);
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
