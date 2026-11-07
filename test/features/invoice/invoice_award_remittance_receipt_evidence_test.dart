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

  test('revoked and re-confirmed receipt invalidates prior consent', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = InvoiceAwardRemittanceReceiptRepository(prefs);
    final proposal = candidate();
    final first = await repo.confirmObservedCredit(
      proposal: proposal,
      receivedAtUtc: DateTime.utc(2026, 10, 7),
      confirmedAtUtc: DateTime.utc(2026, 10, 8),
    );
    expect(repo.isCurrentObservation(
        proposal: proposal, observation: first), isTrue);
    await repo.revokeForProposal(proposal);
    expect(repo.isCurrentObservation(
        proposal: proposal, observation: first), isFalse);
    final replacement = await repo.confirmObservedCredit(
      proposal: proposal,
      receivedAtUtc: DateTime.utc(2026, 10, 7),
      confirmedAtUtc: DateTime.utc(2026, 10, 9),
    );
    expect(first.matches(proposal), isTrue);
    expect(replacement.matches(proposal), isTrue);
    expect(first.sameObservationAs(replacement), isFalse);
    expect(repo.isCurrentObservation(
        proposal: proposal, observation: first), isFalse);
    expect(repo.isCurrentObservation(
        proposal: proposal, observation: replacement), isTrue);
  });

  test('same-timestamp revoke/reconfirm rotates durable consent revision', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = InvoiceAwardRemittanceReceiptRepository(prefs);
    final proposal = candidate();
    final received = DateTime.utc(2026, 10, 7);
    final confirmed = DateTime.utc(2026, 10, 8);
    final first = await repo.confirmObservedCredit(
      proposal: proposal, receivedAtUtc: received, confirmedAtUtc: confirmed,
    );
    expect(first.observationRevision, matches(RegExp(r'^[0-9a-f]{32}$')));
    await repo.revokeForProposal(proposal);
    final replacement = await repo.confirmObservedCredit(
      proposal: proposal, receivedAtUtc: received, confirmedAtUtc: confirmed,
    );
    expect(first.receivedAtUtc, replacement.receivedAtUtc);
    expect(first.confirmedAtUtc, replacement.confirmedAtUtc);
    expect(replacement.observationRevision, isNot(first.observationRevision));
    expect(first.sameObservationAs(replacement), isFalse);
    expect(repo.isCurrentObservation(
        proposal: proposal, observation: first), isFalse);
    expect(repo.isCurrentObservation(
        proposal: proposal, observation: replacement), isTrue);
    expect(repo.readForProposal(proposal)!.observationRevision,
        replacement.observationRevision);
  });

  test('legacy receipt remains readable and malformed revision fails closed', () async {
    final proposal = candidate();
    final legacy = InvoiceAwardRemittanceReceiptEvidence(
      proposalKey: proposal.idempotencyKey,
      awardPeriodId: proposal.awardPeriodId,
      localAccountId: proposal.localAccountId,
      prizeTier: proposal.prizeTier,
      grossAmount: proposal.grossAmount,
      officialFingerprint: proposal.officialDatasetFingerprint,
      receivedAtUtc: DateTime.utc(2026, 10, 7),
      confirmedAtUtc: DateTime.utc(2026, 10, 8),
    );
    final bytes = jsonEncode(<Object>[legacy.toJson()]);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'issue13_remittance_observations_v1': bytes,
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = InvoiceAwardRemittanceReceiptRepository(prefs);
    expect(repo.isCurrentObservation(
        proposal: proposal, observation: legacy), isTrue);
    expect(prefs.getString('issue13_remittance_observations_v1'), bytes);
    final malformed = <String, Object>{
      ...legacy.toJson(), 'observation_revision': 'not-a-valid-revision',
    };
    expect(InvoiceAwardRemittanceReceiptEvidence.fromJson(malformed), isNull);
    await repo.revokeForProposal(proposal);
    final fresh = await repo.confirmObservedCredit(
      proposal: proposal,
      receivedAtUtc: legacy.receivedAtUtc,
      confirmedAtUtc: legacy.confirmedAtUtc,
    );
    expect(legacy.sameObservationAs(fresh), isFalse);
    expect(repo.isCurrentObservation(
        proposal: proposal, observation: legacy), isFalse);
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
  test('corrupt receipt snapshots fail closed and preserve exact audit bytes',
      () async {
    final proposal = candidate();
    final valid = InvoiceAwardRemittanceReceiptEvidence(
      proposalKey: proposal.idempotencyKey,
      awardPeriodId: proposal.awardPeriodId,
      localAccountId: proposal.localAccountId,
      prizeTier: proposal.prizeTier,
      grossAmount: proposal.grossAmount,
      officialFingerprint: proposal.officialDatasetFingerprint,
      receivedAtUtc: DateTime.utc(2026, 10, 7),
      confirmedAtUtc: DateTime.utc(2026, 10, 8),
    );
    final malformed = <String, Object>{
      ...valid.toJson(),
      'observation_revision': 'invalid-revision',
    };
    const key = 'issue13_remittance_observations_v1';
    for (final bytes in <String>[
      '',
      'not-json',
      '{}',
      '[null]',
      jsonEncode(<Object>[valid.toJson(), malformed]),
      jsonEncode(<Object>[valid.toJson(), valid.toJson()]),
    ]) {
      SharedPreferences.setMockInitialValues(<String, Object>{key: bytes});
      final prefs = await SharedPreferences.getInstance();
      final repository = InvoiceAwardRemittanceReceiptRepository(prefs);
      expect(repository.loadAll(), isEmpty);
      expect(repository.readForProposal(proposal), isNull);
      await expectLater(
        repository.confirmObservedCredit(
          proposal: proposal,
          receivedAtUtc: valid.receivedAtUtc,
          confirmedAtUtc: valid.confirmedAtUtc,
        ),
        throwsA(isA<StateError>().having(
          (error) => error.toString(), 'corrupt store',
          contains('REMITTANCE_OBSERVATION_STORE_CORRUPT'),
        )),
      );
      await expectLater(
        repository.revokeForProposal(proposal),
        throwsA(isA<StateError>().having(
          (error) => error.toString(), 'corrupt store',
          contains('REMITTANCE_OBSERVATION_STORE_CORRUPT'),
        )),
      );
      expect(prefs.getString(key), bytes);
    }
  });

  test('stale account or official source cannot revoke another receipt',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = InvoiceAwardRemittanceReceiptRepository(preferences);
    final original = candidate();
    final observation = await repository.confirmObservedCredit(
      proposal: original,
      receivedAtUtc: DateTime.utc(2026, 10, 7),
      confirmedAtUtc: DateTime.utc(2026, 10, 8),
    );
    const key = 'issue13_remittance_observations_v1';
    final before = preferences.getString(key);
    for (final stale in <InvoiceAwardPayoutBookkeepingProposal>[
      candidate(account: 'another-bank'),
      candidate(sha: 'b' * 64),
      candidate(amount: 300),
    ]) {
      expect(stale.idempotencyKey, original.idempotencyKey);
      await expectLater(
        repository.revokeForProposal(stale),
        throwsA(isA<StateError>().having(
          (error) => error.toString(), 'wrong observation identity',
          contains('REMITTANCE_OBSERVATION_IDENTITY_CONFLICT'),
        )),
      );
      expect(preferences.getString(key), before,
          reason: 'a stale revocation must preserve original audit bytes');
      expect(repository.isCurrentObservation(
          proposal: original, observation: observation), isTrue);
    }
    // A missing key must not rewrite unrelated observations.
    await repository.revokeForProposal(
        candidate(tier: 'general-fifth', amount: 1000));
    expect(preferences.getString(key), before);
    await repository.revokeForProposal(original);
    expect(repository.readForProposal(original), isNull);
  });

  test('same proposal key with conflicting identity is not overwritten',
      () async {
    final proposal = candidate();
    final record = InvoiceAwardRemittanceReceiptEvidence(
      proposalKey: proposal.idempotencyKey,
      awardPeriodId: proposal.awardPeriodId,
      localAccountId: 'another-bank',
      prizeTier: proposal.prizeTier,
      grossAmount: proposal.grossAmount,
      officialFingerprint: proposal.officialDatasetFingerprint,
      receivedAtUtc: DateTime.utc(2026, 10, 7),
      confirmedAtUtc: DateTime.utc(2026, 10, 8),
    );
    final bytes = jsonEncode(<Object>[record.toJson()]);
    const key = 'issue13_remittance_observations_v1';
    SharedPreferences.setMockInitialValues(<String, Object>{key: bytes});
    final prefs = await SharedPreferences.getInstance();
    final repository = InvoiceAwardRemittanceReceiptRepository(prefs);
    expect(repository.loadAll(), hasLength(1));
    await expectLater(
      repository.confirmObservedCredit(
        proposal: proposal,
        receivedAtUtc: record.receivedAtUtc,
        confirmedAtUtc: record.confirmedAtUtc,
      ),
      throwsA(isA<StateError>().having(
        (error) => error.toString(), 'identity conflict',
        contains('REMITTANCE_OBSERVATION_IDENTITY_CONFLICT'),
      )),
    );
    expect(prefs.getString(key), bytes);
    expect(repository.readForProposal(proposal), isNull);
  });

}
