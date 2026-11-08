import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/invoice_award_formal_income_posting_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_finance_app/features/invoice/invoice_award_payout_bookkeeping_contract.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud500_production_policy.dart';
import 'package:my_finance_app/features/invoice/invoice_award_remittance_receipt_evidence.dart';

// A deterministic platform-failure witness: no Owner store or native plugin.
class _RejectedWritePreferences implements SharedPreferences {
  _RejectedWritePreferences(this.persistedBytes);

  final String? persistedBytes;
  int writeAttempts = 0;
  int reloadAttempts = 0;

  @override
  String? getString(String key) =>
      key == 'issue13_remittance_observations_v1' ? persistedBytes : null;

  @override
  Future<bool> setString(String key, String value) async {
    writeAttempts++;
    return false;
  }

  @override
  Future<void> reload() async {
    reloadAttempts++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// External-process preference changes are not reflected in the local cache
// until reload(); this fake never accesses Owner storage.
class _ExternalMutationPreferences implements SharedPreferences {
  _ExternalMutationPreferences(this.cachedBytes, this.platformBytes);
  String? cachedBytes;
  String? platformBytes;
  int reloadAttempts = 0;
  int writeAttempts = 0;

  @override
  String? getString(String key) =>
      key == 'issue13_remittance_observations_v1' ? cachedBytes : null;

  @override
  Future<void> reload() async {
    reloadAttempts++;
    cachedBytes = platformBytes;
  }

  @override
  Future<bool> setString(String key, String value) async {
    writeAttempts++;
    cachedBytes = platformBytes = value;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// An awaited native write can yield to another same-isolate repository.
// Keep the first platform write pending to prove no second mutation enters.
class _BarrierPreferences implements SharedPreferences {
  _BarrierPreferences(this.platformBytes) : cachedBytes = platformBytes;

  String? platformBytes;
  String? cachedBytes;
  int writeAttempts = 0;
  int reloadAttempts = 0;
  final firstWriteStarted = Completer<void>();
  final releaseFirstWrite = Completer<void>();

  @override
  String? getString(String key) =>
      key == 'issue13_remittance_observations_v1' ? cachedBytes : null;

  @override
  Future<void> reload() async {
    reloadAttempts++;
    cachedBytes = platformBytes;
  }

  @override
  Future<bool> setString(String key, String value) async {
    writeAttempts++;
    if (writeAttempts == 1) {
      firstWriteStarted.complete();
      await releaseFirstWrite.future;
    }
    cachedBytes = platformBytes = value;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Forbid SQLite access when external receipt authority has been revoked.
class _ForbiddenSqliteDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('UNEXPECTED_SQLITE_TRANSACTION');
}

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


  test('same-isolate concurrent confirms keep one durable revision', () async {
    final proposal = candidate();
    final preferences = _BarrierPreferences(null);
    final firstRepository = InvoiceAwardRemittanceReceiptRepository(preferences);
    final secondRepository = InvoiceAwardRemittanceReceiptRepository(preferences);
    final received = DateTime.utc(2026, 10, 7);
    final confirmed = DateTime.utc(2026, 10, 8);
    final first = firstRepository.confirmObservedCredit(
      proposal: proposal, receivedAtUtc: received, confirmedAtUtc: confirmed,
    );
    await preferences.firstWriteStarted.future;
    final second = secondRepository.confirmObservedCredit(
      proposal: proposal, receivedAtUtc: received, confirmedAtUtc: confirmed,
    );
    await Future<void>.delayed(Duration.zero);
    expect(preferences.writeAttempts, 1,
        reason: 'the second read-modify-write must wait for the first write');
    preferences.releaseFirstWrite.complete();
    final firstReceipt = await first;
    final secondReceipt = await second;
    expect(secondReceipt.observationRevision, firstReceipt.observationRevision);
    expect(preferences.writeAttempts, 1);
    expect(preferences.reloadAttempts, 2);
    expect(preferences.platformBytes,
        jsonEncode(<Object>[firstReceipt.toJson()]));
  });

  test('same-isolate revoke then confirm rotates revision after write', () async {
    final proposal = candidate();
    final original = InvoiceAwardRemittanceReceiptEvidence(
      proposalKey: proposal.idempotencyKey,
      awardPeriodId: proposal.awardPeriodId,
      localAccountId: proposal.localAccountId,
      prizeTier: proposal.prizeTier,
      grossAmount: proposal.grossAmount,
      officialFingerprint: proposal.officialDatasetFingerprint,
      receivedAtUtc: DateTime.utc(2026, 10, 7),
      confirmedAtUtc: DateTime.utc(2026, 10, 8),
      observationRevision: 'a' * 32,
    );
    final preferences = _BarrierPreferences(
        jsonEncode(<Object>[original.toJson()]));
    final revoker = InvoiceAwardRemittanceReceiptRepository(preferences);
    final confirmer = InvoiceAwardRemittanceReceiptRepository(preferences);
    final revoke = revoker.revokeForProposal(
        proposal, expectedObservation: original);
    await preferences.firstWriteStarted.future;
    final confirm = confirmer.confirmObservedCredit(
      proposal: proposal,
      receivedAtUtc: original.receivedAtUtc,
      confirmedAtUtc: original.confirmedAtUtc,
    );
    await Future<void>.delayed(Duration.zero);
    expect(preferences.writeAttempts, 1,
        reason: 'confirmation must not read pre-revocation cached consent');
    preferences.releaseFirstWrite.complete();
    await revoke;
    final replacement = await confirm;
    expect(replacement.sameObservationAs(original), isFalse);
    expect(replacement.observationRevision, isNot(original.observationRevision));
    expect(preferences.writeAttempts, 2);
    expect(preferences.platformBytes,
        jsonEncode(<Object>[replacement.toJson()]));
    expect(confirmer.isCurrentObservation(
        proposal: proposal, observation: replacement), isTrue);
  });


  test('posting holds same-isolate consent fence through awaited accounts',
      () async {
    final proposal = candidate();
    final receipt = InvoiceAwardRemittanceReceiptEvidence(
      proposalKey: proposal.idempotencyKey,
      awardPeriodId: proposal.awardPeriodId,
      localAccountId: proposal.localAccountId,
      prizeTier: proposal.prizeTier,
      grossAmount: proposal.grossAmount,
      officialFingerprint: proposal.officialDatasetFingerprint,
      receivedAtUtc: DateTime.utc(2026, 10, 7),
      confirmedAtUtc: DateTime.utc(2026, 10, 8),
      observationRevision: 'e' * 32,
    );
    final original = jsonEncode(<Object>[receipt.toJson()]);
    final preferences = _ExternalMutationPreferences(original, original);
    final accountsStarted = Completer<void>();
    final releaseAccounts = Completer<List<AccountRecord>>();
    var databases = 0;
    final service = InvoiceAwardFormalIncomePostingService.forIsolatedTest(
      preferencesProvider: () async => preferences,
      accountsProvider: () {
        accountsStarted.complete();
        return releaseAccounts.future;
      },
      databaseProvider: () async {
        databases++;
        return _ForbiddenSqliteDatabase();
      },
    );
    final posting = service.post(
      proposal: proposal, receipt: receipt,
      authorizedAtUtc: DateTime.utc(2026, 10, 9),
    );
    await accountsStarted.future;
    final revocation = InvoiceAwardRemittanceReceiptRepository(preferences)
        .revokeForProposal(proposal, expectedObservation: receipt);
    await Future<void>.delayed(Duration.zero);
    expect(preferences.writeAttempts, 0,
        reason: 'revocation must wait until the posting lease is released');
    expect(preferences.platformBytes, original);
    releaseAccounts.complete(<AccountRecord>[]);
    await expectLater(posting, throwsA(isA<StateError>().having(
      (e) => e.toString(), 'account rejection',
      contains('INVOICE_AWARD_POSTING_ACCOUNT_UNAVAILABLE'))));
    await revocation;
    expect(databases, 0);
    expect(preferences.writeAttempts, 1);
    expect(preferences.platformBytes, '[]');
  });

  test('pending same-isolate revocation blocks formal posting authority',
      () async {
    final proposal = candidate();
    final receipt = InvoiceAwardRemittanceReceiptEvidence(
      proposalKey: proposal.idempotencyKey,
      awardPeriodId: proposal.awardPeriodId,
      localAccountId: proposal.localAccountId,
      prizeTier: proposal.prizeTier,
      grossAmount: proposal.grossAmount,
      officialFingerprint: proposal.officialDatasetFingerprint,
      receivedAtUtc: DateTime.utc(2026, 10, 7),
      confirmedAtUtc: DateTime.utc(2026, 10, 8),
      observationRevision: 'f' * 32,
    );
    final original = jsonEncode(<Object>[receipt.toJson()]);
    final preferences = _BarrierPreferences(original);
    final repository = InvoiceAwardRemittanceReceiptRepository(preferences);
    final revocation = repository.revokeForProposal(
        proposal, expectedObservation: receipt);
    await preferences.firstWriteStarted.future;
    var accounts = 0;
    var databases = 0;
    final service = InvoiceAwardFormalIncomePostingService.forIsolatedTest(
      preferencesProvider: () async => preferences,
      accountsProvider: () async {
        accounts++;
        return <AccountRecord>[];
      },
      databaseProvider: () async {
        databases++;
        return _ForbiddenSqliteDatabase();
      },
    );
    final posting = service.post(
      proposal: proposal, receipt: receipt,
      authorizedAtUtc: DateTime.utc(2026, 10, 9),
    );
    await Future<void>.delayed(Duration.zero);
    expect(accounts, 0,
        reason: 'posting cannot pass pending revocation before persistence');
    expect(databases, 0);
    preferences.releaseFirstWrite.complete();
    await revocation;
    await expectLater(posting, throwsA(isA<StateError>().having(
      (e) => e.toString(), 'revoked receipt',
      contains('INVOICE_AWARD_POSTING_RECEIPT_NOT_CURRENT'))));
    expect(accounts, 0);
    expect(databases, 0);
    expect(preferences.writeAttempts, 1);
    expect(preferences.platformBytes, '[]');
  });

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

  test('fresh authority rejects external revoke/replacement without writes', () async {
    final proposal = candidate();
    InvoiceAwardRemittanceReceiptEvidence observation(String revision) =>
        InvoiceAwardRemittanceReceiptEvidence(
          proposalKey: proposal.idempotencyKey,
          awardPeriodId: proposal.awardPeriodId,
          localAccountId: proposal.localAccountId,
          prizeTier: proposal.prizeTier,
          grossAmount: proposal.grossAmount,
          officialFingerprint: proposal.officialDatasetFingerprint,
          receivedAtUtc: DateTime.utc(2026, 10, 7),
          confirmedAtUtc: DateTime.utc(2026, 10, 8),
          observationRevision: revision,
        );
    final receipt = observation('a' * 32);
    final original = jsonEncode(<Object>[receipt.toJson()]);
    final replacement = jsonEncode(<Object>[observation('b' * 32).toJson()]);
    for (final external in <String>['[]', replacement]) {
      final prefs = _ExternalMutationPreferences(original, external);
      final repo = InvoiceAwardRemittanceReceiptRepository(prefs);
      expect(repo.isCurrentObservation(proposal: proposal, observation: receipt),
          isTrue, reason: 'synchronous cache is stale');
      expect(await repo.isCurrentObservationFresh(
          proposal: proposal, observation: receipt), isFalse);
      expect(prefs.reloadAttempts, 1);
      expect(prefs.writeAttempts, 0);
      expect(prefs.platformBytes, external);
    }
    final intact = _ExternalMutationPreferences(original, original);
    expect(await InvoiceAwardRemittanceReceiptRepository(intact)
        .isCurrentObservationFresh(proposal: proposal, observation: receipt),
        isTrue);
    expect(intact.writeAttempts, 0);
  });

  test('posting rejects external revoked cache before account and SQLite', () async {
    final proposal = candidate();
    final receipt = InvoiceAwardRemittanceReceiptEvidence(
      proposalKey: proposal.idempotencyKey,
      awardPeriodId: proposal.awardPeriodId,
      localAccountId: proposal.localAccountId,
      prizeTier: proposal.prizeTier,
      grossAmount: proposal.grossAmount,
      officialFingerprint: proposal.officialDatasetFingerprint,
      receivedAtUtc: DateTime.utc(2026, 10, 7),
      confirmedAtUtc: DateTime.utc(2026, 10, 8),
      observationRevision: 'c' * 32,
    );
    final prefs = _ExternalMutationPreferences(
        jsonEncode(<Object>[receipt.toJson()]), '[]');
    var accounts = 0;
    var databases = 0;
    final service = InvoiceAwardFormalIncomePostingService.forIsolatedTest(
      preferencesProvider: () async => prefs,
      accountsProvider: () async {
        accounts++;
        throw StateError('UNEXPECTED_ACCOUNT_ACCESS');
      },
      databaseProvider: () async {
        databases++;
        throw StateError('UNEXPECTED_SQLITE_ACCESS');
      },
    );
    await expectLater(service.post(proposal: proposal, receipt: receipt,
        authorizedAtUtc: DateTime.utc(2026, 10, 9)),
        throwsA(isA<StateError>().having(
          (e) => e.toString(), 'revoked receipt',
          contains('INVOICE_AWARD_POSTING_RECEIPT_NOT_CURRENT'))));
    expect(accounts, 0);
    expect(databases, 0);
    expect(prefs.writeAttempts, 0);
    expect(prefs.platformBytes, '[]');
  });

  test('posting rechecks external revoke after awaited account lookup', () async {
    final proposal = candidate();
    final receipt = InvoiceAwardRemittanceReceiptEvidence(
      proposalKey: proposal.idempotencyKey,
      awardPeriodId: proposal.awardPeriodId,
      localAccountId: proposal.localAccountId,
      prizeTier: proposal.prizeTier,
      grossAmount: proposal.grossAmount,
      officialFingerprint: proposal.officialDatasetFingerprint,
      receivedAtUtc: DateTime.utc(2026, 10, 7),
      confirmedAtUtc: DateTime.utc(2026, 10, 8),
      observationRevision: 'd' * 32,
    );
    final original = jsonEncode(<Object>[receipt.toJson()]);
    final prefs = _ExternalMutationPreferences(original, original);
    var databases = 0;
    final service = InvoiceAwardFormalIncomePostingService.forIsolatedTest(
      preferencesProvider: () async => prefs,
      accountsProvider: () async {
        prefs.platformBytes = '[]';
        return <AccountRecord>[
          const AccountRecord(id: 'bank-1', name: '隔離銀行',
              type: AccountType.bank, initialBalance: 0, sortOrder: 0),
        ];
      },
      databaseProvider: () async {
        databases++;
        return _ForbiddenSqliteDatabase();
      },
    );
    await expectLater(service.post(proposal: proposal, receipt: receipt,
        authorizedAtUtc: DateTime.utc(2026, 10, 9)),
        throwsA(isA<StateError>().having(
          (e) => e.toString(), 'revoked after account read',
          contains('INVOICE_AWARD_POSTING_RECEIPT_NOT_CURRENT'))));
    expect(databases, 1);
    expect(prefs.reloadAttempts, 2);
    expect(prefs.writeAttempts, 0);
    expect(prefs.platformBytes, '[]');
  });

  test('external same-key consent blocks stale cached confirmation', () async {
    final stale = candidate(account: 'bank-1');
    final external = candidate(account: 'bank-2');
    expect(stale.idempotencyKey, external.idempotencyKey);
    final externalBytes = jsonEncode(<Object>[
      InvoiceAwardRemittanceReceiptEvidence(
        proposalKey: external.idempotencyKey,
        awardPeriodId: external.awardPeriodId,
        localAccountId: external.localAccountId,
        prizeTier: external.prizeTier,
        grossAmount: external.grossAmount,
        officialFingerprint: external.officialDatasetFingerprint,
        receivedAtUtc: DateTime.utc(2026, 10, 7),
        confirmedAtUtc: DateTime.utc(2026, 10, 8),
      ).toJson(),
    ]);
    final preferences = _ExternalMutationPreferences(null, externalBytes);
    final repository = InvoiceAwardRemittanceReceiptRepository(preferences);
    await expectLater(
      repository.confirmObservedCredit(
        proposal: stale,
        receivedAtUtc: DateTime.utc(2026, 10, 7),
        confirmedAtUtc: DateTime.utc(2026, 10, 8),
      ),
      throwsA(isA<StateError>().having(
        (e) => e.toString(), 'identity conflict',
        contains('REMITTANCE_OBSERVATION_IDENTITY_CONFLICT'),
      )),
    );
    expect(preferences.reloadAttempts, 1);
    expect(preferences.writeAttempts, 0);
    expect(preferences.platformBytes, externalBytes);
    expect(repository.readForProposal(external)?.localAccountId, 'bank-2');
  });

  test('external replacement prevents stale same-key revocation', () async {
    final stale = candidate(account: 'bank-1');
    final external = candidate(account: 'bank-2');
    expect(stale.idempotencyKey, external.idempotencyKey);
    String bytes(InvoiceAwardPayoutBookkeepingProposal proposal) =>
        jsonEncode(<Object>[
          InvoiceAwardRemittanceReceiptEvidence(
            proposalKey: proposal.idempotencyKey,
            awardPeriodId: proposal.awardPeriodId,
            localAccountId: proposal.localAccountId,
            prizeTier: proposal.prizeTier,
            grossAmount: proposal.grossAmount,
            officialFingerprint: proposal.officialDatasetFingerprint,
            receivedAtUtc: DateTime.utc(2026, 10, 7),
            confirmedAtUtc: DateTime.utc(2026, 10, 8),
          ).toJson(),
        ]);
    final externalBytes = bytes(external);
    final preferences = _ExternalMutationPreferences(
        bytes(stale), externalBytes);
    final repository = InvoiceAwardRemittanceReceiptRepository(preferences);
    await expectLater(
      repository.revokeForProposal(
          stale,
          expectedObservation: InvoiceAwardRemittanceReceiptEvidence.fromJson(
              (jsonDecode(bytes(stale)) as List<dynamic>).single)!,
        ),
      throwsA(isA<StateError>().having(
        (e) => e.toString(), 'identity conflict',
        contains('REMITTANCE_OBSERVATION_IDENTITY_CONFLICT'),
      )),
    );
    expect(preferences.reloadAttempts, 1);
    expect(preferences.writeAttempts, 0);
    expect(preferences.platformBytes, externalBytes);
    expect(repository.readForProposal(external)?.localAccountId, 'bank-2');
  });


  test('same-key same-account external re-confirm survives stale revocation',
      () async {
    final proposal = candidate();
    InvoiceAwardRemittanceReceiptEvidence receipt(String revision) =>
        InvoiceAwardRemittanceReceiptEvidence(
          proposalKey: proposal.idempotencyKey,
          awardPeriodId: proposal.awardPeriodId,
          localAccountId: proposal.localAccountId,
          prizeTier: proposal.prizeTier,
          grossAmount: proposal.grossAmount,
          officialFingerprint: proposal.officialDatasetFingerprint,
          receivedAtUtc: DateTime.utc(2026, 10, 7),
          confirmedAtUtc: DateTime.utc(2026, 10, 8),
          observationRevision: revision,
        );
    final stale = receipt('a' * 32);
    final replacement = receipt('b' * 32);
    final staleBytes = jsonEncode(<Object>[stale.toJson()]);
    final replacementBytes = jsonEncode(<Object>[replacement.toJson()]);
    // UI-captured revision governs even if the cache has already reloaded.
    for (final cached in <String>[staleBytes, replacementBytes]) {
      final preferences =
          _ExternalMutationPreferences(cached, replacementBytes);
      final repository = InvoiceAwardRemittanceReceiptRepository(preferences);
      await expectLater(
        repository.revokeForProposal(proposal, expectedObservation: stale),
        throwsA(isA<StateError>().having(
          (e) => e.toString(), 'revision conflict',
          contains('REMITTANCE_OBSERVATION_REVISION_CONFLICT'),
        )),
      );
      expect(preferences.reloadAttempts, 1);
      expect(preferences.writeAttempts, 0);
      expect(preferences.platformBytes, replacementBytes);
      expect(repository.isCurrentObservation(
          proposal: proposal, observation: replacement), isTrue);
    }
  });

  test('receipt confirmation rejects failed platform persistence', () async {
    final preferences = _RejectedWritePreferences(null);
    final repository = InvoiceAwardRemittanceReceiptRepository(preferences);
    final proposal = candidate();
    await expectLater(
      repository.confirmObservedCredit(
        proposal: proposal,
        receivedAtUtc: DateTime.utc(2026, 10, 7),
        confirmedAtUtc: DateTime.utc(2026, 10, 8),
      ),
      throwsA(isA<StateError>().having(
        (e) => e.toString(), 'persistence failure',
        contains('REMITTANCE_OBSERVATION_PERSIST_FAILED'),
      )),
    );
    expect(preferences.writeAttempts, 1);
    // Reload once before mutation, then again to discard the optimistic
    // cache after setString(false). Failed persistence remains fail-closed.
    expect(preferences.reloadAttempts, 2);
    expect(repository.readForProposal(proposal), isNull);
  });

  test('receipt revocation rejects failed platform persistence', () async {
    final proposal = candidate();
    final original = InvoiceAwardRemittanceReceiptEvidence(
      proposalKey: proposal.idempotencyKey,
      awardPeriodId: proposal.awardPeriodId,
      localAccountId: proposal.localAccountId,
      prizeTier: proposal.prizeTier,
      grossAmount: proposal.grossAmount,
      officialFingerprint: proposal.officialDatasetFingerprint,
      receivedAtUtc: DateTime.utc(2026, 10, 7),
      confirmedAtUtc: DateTime.utc(2026, 10, 8),
    );
    final originalBytes = jsonEncode(<Object>[original.toJson()]);
    final preferences = _RejectedWritePreferences(originalBytes);
    final repository = InvoiceAwardRemittanceReceiptRepository(preferences);
    await expectLater(
      repository.revokeForProposal(proposal, expectedObservation: original),
      throwsA(isA<StateError>().having(
        (e) => e.toString(), 'persistence failure',
        contains('REMITTANCE_OBSERVATION_PERSIST_FAILED'),
      )),
    );
    expect(preferences.writeAttempts, 1);
    // Reload once before mutation, then again to discard the optimistic
    // cache after setString(false). Failed persistence remains fail-closed.
    expect(preferences.reloadAttempts, 2);
    expect(preferences.getString('issue13_remittance_observations_v1'),
        originalBytes);
    expect(repository.isCurrentObservation(
        proposal: proposal, observation: original), isTrue);
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
    await repo.revokeForProposal(proposal, expectedObservation: first);
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
    await repo.revokeForProposal(proposal, expectedObservation: first);
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
    await repo.revokeForProposal(proposal, expectedObservation: legacy);
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
    final confirmed = await repo.confirmObservedCredit(
      proposal: proposal,
      receivedAtUtc: DateTime.utc(2026, 10, 7),
      confirmedAtUtc: DateTime.utc(2026, 10, 8),
    );
    await repo.revokeForProposal(proposal, expectedObservation: confirmed);
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
        repository.revokeForProposal(proposal, expectedObservation: valid),
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
        repository.revokeForProposal(stale, expectedObservation: observation),
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
        candidate(tier: 'general-fifth', amount: 1000),
        expectedObservation: observation);
    expect(preferences.getString(key), before);
    await repository.revokeForProposal(original, expectedObservation: observation);
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
