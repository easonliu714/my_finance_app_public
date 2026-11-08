import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'invoice_award_payout_bookkeeping_contract.dart';
import 'invoice_award_cloud500_production_policy.dart';

/// Manual observation, not MOF or bank-verified settlement.
class InvoiceAwardRemittanceReceiptEvidence {
  const InvoiceAwardRemittanceReceiptEvidence({
    required this.proposalKey,
    required this.awardPeriodId,
    required this.localAccountId,
    required this.prizeTier,
    required this.grossAmount,
    required this.officialFingerprint,
    required this.receivedAtUtc,
    required this.confirmedAtUtc,
    this.observationRevision,
  });

  static const contractVersion = 'issue13-remittance-observation-v1';
  final String proposalKey;
  final String awardPeriodId;
  final String localAccountId;
  final String prizeTier;
  final int grossAmount;
  final String officialFingerprint;
  final DateTime receivedAtUtc;
  final DateTime confirmedAtUtc;
  // Legacy observations have no revision; new receipts always have one.
  final String? observationRevision;

  bool matches(InvoiceAwardPayoutBookkeepingProposal proposal) =>
      proposal.hasValidProvenance &&
      proposalKey == proposal.idempotencyKey &&
      awardPeriodId == proposal.awardPeriodId &&
      localAccountId == proposal.localAccountId &&
      prizeTier == proposal.prizeTier &&
      grossAmount == proposal.grossAmount &&
      officialFingerprint.toLowerCase() ==
          proposal.officialDatasetFingerprint.toLowerCase() &&
      receivedAtUtc.isUtc &&
      confirmedAtUtc.isUtc &&
      !receivedAtUtc.isBefore(proposal.externalRemittanceEligibleAt) &&
      !confirmedAtUtc.isBefore(receivedAtUtc);

  // A modal is authorized against one persisted observation, not just its
  // proposal key. Revocation followed by re-confirmation invalidates the old
  // receipt even when period, account and amount remain identical.
  bool sameObservationAs(InvoiceAwardRemittanceReceiptEvidence other) =>
      proposalKey == other.proposalKey &&
      awardPeriodId == other.awardPeriodId &&
      localAccountId == other.localAccountId &&
      prizeTier == other.prizeTier &&
      grossAmount == other.grossAmount &&
      officialFingerprint == other.officialFingerprint &&
      receivedAtUtc == other.receivedAtUtc &&
      confirmedAtUtc == other.confirmedAtUtc &&
      observationRevision == other.observationRevision;

  Map<String, Object> toJson() => <String, Object>{
        'version': contractVersion,
        'key': proposalKey,
        'period': awardPeriodId,
        'account': localAccountId,
        'tier': prizeTier,
        'amount': grossAmount,
        'fingerprint': officialFingerprint,
        'received_utc': receivedAtUtc.toIso8601String(),
        'confirmed_utc': confirmedAtUtc.toIso8601String(),
        if (observationRevision != null)
          'observation_revision': observationRevision!,
      };

  static InvoiceAwardRemittanceReceiptEvidence? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> || raw['version'] != contractVersion) {
      return null;
    }
    final amount = raw['amount'];
    final received = DateTime.tryParse(raw['received_utc']?.toString() ?? '');
    final confirmed = DateTime.tryParse(raw['confirmed_utc']?.toString() ?? '');
    final fingerprint = raw['fingerprint']?.toString() ?? '';
    final revision = raw['observation_revision'];
    // Preserve old revisionless rows, but fail closed on invalid new metadata.
    if (revision != null &&
        (revision is! String ||
            !RegExp(r'^[0-9a-f]{32}$').hasMatch(revision))) {
      return null;
    }
    if (amount is! int || amount <= 0 || received == null ||
        confirmed == null || !received.isUtc || !confirmed.isUtc ||
        received.isAfter(confirmed) ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(fingerprint)) {
      return null;
    }
    final item = InvoiceAwardRemittanceReceiptEvidence(
      proposalKey: raw['key']?.toString() ?? '',
      awardPeriodId: raw['period']?.toString() ?? '',
      localAccountId: raw['account']?.toString() ?? '',
      prizeTier: raw['tier']?.toString() ?? '',
      grossAmount: amount,
      officialFingerprint: fingerprint,
      receivedAtUtc: received,
      confirmedAtUtc: confirmed,
      observationRevision: revision as String?,
    );
    if (item.proposalKey.isEmpty || item.awardPeriodId.isEmpty ||
        item.localAccountId.isEmpty || item.prizeTier.isEmpty) {
      return null;
    }
    return item;
  }
}

// New manual consent gets a fresh 128-bit identity independent of timestamps.
String _newObservationRevision() {
  final random = Random.secure();
  return List<int>.generate(16, (_) => random.nextInt(256))
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

class InvoiceAwardRemittanceReceiptRepository {
  InvoiceAwardRemittanceReceiptRepository(this.preferences);
  final SharedPreferences preferences;
  static const _key = 'issue13_remittance_observations_v1';

  // Corrupt or duplicated persisted observations invalidate the entire
  // authorization snapshot, not merely the individual malformed row.
  List<InvoiceAwardRemittanceReceiptEvidence>? _decodeAllStrict() {
    final source = preferences.getString(_key);
    if (source == null) {
      return const <InvoiceAwardRemittanceReceiptEvidence>[];
    }
    if (source.trim().isEmpty) return null;
    try {
      final raw = jsonDecode(source);
      if (raw is! List<dynamic>) return null;
      final rows = <InvoiceAwardRemittanceReceiptEvidence>[];
      final seen = <String>{};
      for (final value in raw) {
        final item = InvoiceAwardRemittanceReceiptEvidence.fromJson(value);
        if (item == null || !seen.add(item.proposalKey)) return null;
        rows.add(item);
      }
      return List<InvoiceAwardRemittanceReceiptEvidence>.unmodifiable(rows);
    } on FormatException {
      return null;
    }
  }

  List<InvoiceAwardRemittanceReceiptEvidence> loadAll() =>
      _decodeAllStrict() ?? const <InvoiceAwardRemittanceReceiptEvidence>[];

  // Mutations must preserve corrupt original bytes for independent audit.
  List<InvoiceAwardRemittanceReceiptEvidence> _readAllForMutation() {
    final rows = _decodeAllStrict();
    if (rows == null) {
      throw StateError('REMITTANCE_OBSERVATION_STORE_CORRUPT');
    }
    return rows;
  }

  InvoiceAwardRemittanceReceiptEvidence? readForProposal(
      InvoiceAwardPayoutBookkeepingProposal proposal) {
    for (final item in loadAll()) {
      if (item.matches(proposal)) {
        return item;
      }
    }
    return null;
  }

  // Read the durable observation after explicit UI approval. A cached
  // receipt must not survive a revoke/re-confirm sequence.
  bool isCurrentObservation({
    required InvoiceAwardPayoutBookkeepingProposal proposal,
    required InvoiceAwardRemittanceReceiptEvidence observation,
  }) {
    if (!observation.matches(proposal)) return false;
    final current = readForProposal(proposal);
    return current != null && current.sameObservationAs(observation);
  }

  Future<InvoiceAwardRemittanceReceiptEvidence> confirmObservedCredit({
    required InvoiceAwardPayoutBookkeepingProposal proposal,
    required DateTime receivedAtUtc,
    required DateTime confirmedAtUtc,
  }) async {
    // Owner option C: block new cloud-500 receipt writes at the repository
    // boundary, including direct callers bypassing the proposal planner.
    // Historical observations remain readable for audit and are not deleted.
    if (proposal.isDeferredCloud500Prize) {
      throw StateError(Cloud500ProductionPolicy.deferredCode);
    }
    if (!proposal.hasValidProvenance || !receivedAtUtc.isUtc ||
        !confirmedAtUtc.isUtc ||
        receivedAtUtc.isBefore(proposal.externalRemittanceEligibleAt) ||
        receivedAtUtc.isAfter(confirmedAtUtc)) {
      throw StateError('REMITTANCE_OBSERVATION_NOT_AUTHORIZED');
    }
    // SharedPreferences caches per instance; reload before read-modify-write
    // to reject another process's newer same-key receipt rather than
    // overwriting it from a stale cache. This is not cross-process CAS.
    await preferences.reload();
    final persisted = _readAllForMutation();
    for (final item in persisted) {
      if (item.proposalKey == proposal.idempotencyKey) {
        // An existing key with a different identity is not an overwrite grant.
        if (!item.matches(proposal)) {
          throw StateError('REMITTANCE_OBSERVATION_IDENTITY_CONFLICT');
        }
        return item;
      }
    }
    final record = InvoiceAwardRemittanceReceiptEvidence(
      proposalKey: proposal.idempotencyKey,
      awardPeriodId: proposal.awardPeriodId,
      localAccountId: proposal.localAccountId,
      prizeTier: proposal.prizeTier,
      grossAmount: proposal.grossAmount,
      officialFingerprint: proposal.officialDatasetFingerprint,
      receivedAtUtc: receivedAtUtc,
      confirmedAtUtc: confirmedAtUtc,
      observationRevision: _newObservationRevision(),
    );
    final rows = persisted
        .where((value) => value.proposalKey != record.proposalKey)
        .toList(growable: true)
      ..add(record);
    rows.sort((a, b) => a.proposalKey.compareTo(b.proposalKey));
    // SharedPreferences reports platform persistence success as a boolean.
    // A failed write must never be presented as confirmed/revoked consent.
    // Reload to discard any optimistic in-memory cache on explicit failure.
    final writeSucceeded = await preferences.setString(_key,
        jsonEncode(rows.map((value) => value.toJson()).toList()));
    if (!writeSucceeded) {
      await preferences.reload();
      throw StateError('REMITTANCE_OBSERVATION_PERSIST_FAILED');
    }
    return record;
  }

  Future<void> revokeForProposal(
      InvoiceAwardPayoutBookkeepingProposal proposal) async {
    // Re-read external state before revocation: a stale cached receipt
    // must not erase a different process's newer same-key audit record.
    await preferences.reload();
    final persisted = _readAllForMutation();
    final matches = persisted
        .where((value) => value.proposalKey == proposal.idempotencyKey)
        .toList(growable: false);
    if (matches.isEmpty) return;
    // The stable key omits account, amount and official-source fingerprint.
    // A stale page must not erase a different observation's audit evidence.
    if (!matches.single.matches(proposal)) {
      throw StateError('REMITTANCE_OBSERVATION_IDENTITY_CONFLICT');
    }
    final rows = persisted
        .where((value) => value.proposalKey != proposal.idempotencyKey)
        .toList();
    // SharedPreferences reports platform persistence success as a boolean.
    // A failed write must never be presented as confirmed/revoked consent.
    // Reload to discard any optimistic in-memory cache on explicit failure.
    final writeSucceeded = await preferences.setString(_key,
        jsonEncode(rows.map((value) => value.toJson()).toList()));
    if (!writeSucceeded) {
      await preferences.reload();
      throw StateError('REMITTANCE_OBSERVATION_PERSIST_FAILED');
    }
  }
}

/// Receipt observation never directly authorizes posting.
class InvoiceAwardRemittanceCreditReadiness {
  const InvoiceAwardRemittanceCreditReadiness({
    required this.proposal, required this.observation,
  });
  final InvoiceAwardPayoutBookkeepingProposal proposal;
  final InvoiceAwardRemittanceReceiptEvidence? observation;
  bool get isUserObservedOnly => observation?.matches(proposal) == true;
  bool get isExternallyVerifiedBankCredit => false;
  bool get canAutomaticallyPostFormalIncome => false;
}
