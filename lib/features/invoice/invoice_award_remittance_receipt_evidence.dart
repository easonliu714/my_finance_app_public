import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'invoice_award_payout_bookkeeping_contract.dart';

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
      };

  static InvoiceAwardRemittanceReceiptEvidence? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> || raw['version'] != contractVersion) {
      return null;
    }
    final amount = raw['amount'];
    final received = DateTime.tryParse(raw['received_utc']?.toString() ?? '');
    final confirmed = DateTime.tryParse(raw['confirmed_utc']?.toString() ?? '');
    final fingerprint = raw['fingerprint']?.toString() ?? '';
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
    );
    if (item.proposalKey.isEmpty || item.awardPeriodId.isEmpty ||
        item.localAccountId.isEmpty || item.prizeTier.isEmpty) {
      return null;
    }
    return item;
  }
}

class InvoiceAwardRemittanceReceiptRepository {
  InvoiceAwardRemittanceReceiptRepository(this.preferences);
  final SharedPreferences preferences;
  static const _key = 'issue13_remittance_observations_v1';

  List<InvoiceAwardRemittanceReceiptEvidence> loadAll() {
    final source = preferences.getString(_key);
    if (source == null || source.isEmpty) {
      return const <InvoiceAwardRemittanceReceiptEvidence>[];
    }
    try {
      final raw = jsonDecode(source);
      if (raw is! List<dynamic>) {
        return const <InvoiceAwardRemittanceReceiptEvidence>[];
      }
      return List<InvoiceAwardRemittanceReceiptEvidence>.unmodifiable(
        raw.map(InvoiceAwardRemittanceReceiptEvidence.fromJson)
            .whereType<InvoiceAwardRemittanceReceiptEvidence>(),
      );
    } on FormatException {
      return const <InvoiceAwardRemittanceReceiptEvidence>[];
    }
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

  Future<InvoiceAwardRemittanceReceiptEvidence> confirmObservedCredit({
    required InvoiceAwardPayoutBookkeepingProposal proposal,
    required DateTime receivedAtUtc,
    required DateTime confirmedAtUtc,
  }) async {
    if (!proposal.hasValidProvenance || !receivedAtUtc.isUtc ||
        !confirmedAtUtc.isUtc ||
        receivedAtUtc.isBefore(proposal.externalRemittanceEligibleAt) ||
        receivedAtUtc.isAfter(confirmedAtUtc)) {
      throw StateError('REMITTANCE_OBSERVATION_NOT_AUTHORIZED');
    }
    final existing = readForProposal(proposal);
    if (existing != null) {
      return existing;
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
    );
    final rows = loadAll()
        .where((value) => value.proposalKey != record.proposalKey)
        .toList(growable: true)
      ..add(record);
    rows.sort((a, b) => a.proposalKey.compareTo(b.proposalKey));
    await preferences.setString(_key,
        jsonEncode(rows.map((value) => value.toJson()).toList()));
    return record;
  }

  Future<void> revokeForProposal(
      InvoiceAwardPayoutBookkeepingProposal proposal) async {
    final rows = loadAll()
        .where((value) => value.proposalKey != proposal.idempotencyKey)
        .toList();
    await preferences.setString(_key,
        jsonEncode(rows.map((value) => value.toJson()).toList()));
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
