import 'dart:convert';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:shared_preferences/shared_preferences.dart';

import 'existing_invoice_award_cloud_batch_matcher.dart';
import 'invoice_award_cloud500_production_policy.dart';

enum InvoiceAwardCloudEligibilityUserDecision { eligible, ineligible }

class InvoiceAwardCloudEligibilityConfirmation {
  const InvoiceAwardCloudEligibilityConfirmation({
    required this.periodId,
    required this.candidateKey,
    required this.candidateSourceProvenance,
    required this.tierCode,
    required this.grossAmount,
    required this.officialPdfSha256,
    required this.decision,
    required this.confirmedAtUtc,
  });

  static const String reviewContractVersion =
      'issue13-cloud-eligibility-user-review-v1';

  final String periodId;
  final String candidateKey;
  final String candidateSourceProvenance;
  final String tierCode;
  final int grossAmount;
  final String officialPdfSha256;
  final InvoiceAwardCloudEligibilityUserDecision decision;
  final DateTime confirmedAtUtc;

  bool get hasValidProvenance =>
      periodId.trim().isNotEmpty &&
      candidateKey.trim().isNotEmpty &&
      candidateSourceProvenance.trim().isNotEmpty &&
      tierCode.trim().isNotEmpty &&
      grossAmount > 0 &&
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(officialPdfSha256) &&
      confirmedAtUtc.isUtc;

  bool get confirmsEligibility =>
      decision == InvoiceAwardCloudEligibilityUserDecision.eligible &&
      hasValidProvenance;
  bool get confirmsIneligibility =>
      decision == InvoiceAwardCloudEligibilityUserDecision.ineligible &&
      hasValidProvenance;
  // Owner C: a historical user decision is evidence, never release authority
  // for a deferred cloud-500 award. Other cloud tiers retain their consent.
  bool canAuthorizeFutureBookkeepingEligibilityForBuild({
    required bool isReleaseBuild,
  }) =>
      confirmsEligibility &&
      !Cloud500ProductionPolicy.blocksCloud500PersistenceForBuild(
        tierCode: tierCode,
        isReleaseBuild: isReleaseBuild,
      );

  bool get canAuthorizeFutureBookkeepingEligibility =>
      canAuthorizeFutureBookkeepingEligibilityForBuild(
        isReleaseBuild: kReleaseMode,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'contract_version': reviewContractVersion,
        'period_id': periodId,
        'candidate_key': candidateKey,
        'candidate_source_provenance': candidateSourceProvenance,
        'tier_code': tierCode,
        'gross_amount': grossAmount,
        'official_pdf_sha256': officialPdfSha256,
        'decision': decision.name,
        'confirmed_at_utc': confirmedAtUtc.toIso8601String(),
      };

  static InvoiceAwardCloudEligibilityConfirmation? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> ||
        raw['contract_version'] != reviewContractVersion) {
      return null;
    }
    InvoiceAwardCloudEligibilityUserDecision? decision;
    for (final value in InvoiceAwardCloudEligibilityUserDecision.values) {
      if (value.name == raw['decision']?.toString()) {
        decision = value;
        break;
      }
    }
    final at = DateTime.tryParse(raw['confirmed_at_utc']?.toString() ?? '');
    final amount = raw['gross_amount'];
    if (decision == null || at == null || amount is! num) {
      return null;
    }
    final record = InvoiceAwardCloudEligibilityConfirmation(
      periodId: raw['period_id']?.toString() ?? '',
      candidateKey: raw['candidate_key']?.toString() ?? '',
      candidateSourceProvenance:
          raw['candidate_source_provenance']?.toString() ?? '',
      tierCode: raw['tier_code']?.toString() ?? '',
      grossAmount: amount.toInt(),
      officialPdfSha256: raw['official_pdf_sha256']?.toString() ?? '',
      decision: decision,
      confirmedAtUtc: at.toUtc(),
    );
    return record.hasValidProvenance ? record : null;
  }
}

class InvoiceAwardCloudEligibilityConfirmationRepository {
  InvoiceAwardCloudEligibilityConfirmationRepository(this.preferences);
  final SharedPreferences preferences;
  static const _recordsKey='issue13_cloud_eligibility_confirmations_v1';

  List<InvoiceAwardCloudEligibilityConfirmation> loadAll() {
    final raw=preferences.getString(_recordsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    try {
      final decoded=jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        return const [];
      }
      return List<InvoiceAwardCloudEligibilityConfirmation>.unmodifiable(
        decoded.map(InvoiceAwardCloudEligibilityConfirmation.fromJson)
          .whereType<InvoiceAwardCloudEligibilityConfirmation>());
    } on FormatException { return const []; }
  }

  InvoiceAwardCloudEligibilityConfirmation? readForEvaluation({
    required String periodId,
    required ExistingInvoiceAwardCloudEvaluation evaluation,
  }) {
    final tier=evaluation.selectedTierCode;
    final sha=evaluation.pdfSha256;
    // Reject stale release authority before reading historical preferences.
    if (tier != null &&
        Cloud500ProductionPolicy.blocksCloud500Persistence(tier)) {
      return null;
    }
    if (tier == null ||
        sha == null ||
        evaluation.status !=
            ExistingInvoiceAwardCloudEvaluationStatus.matchedReviewRequired) {
      return null;
    }
    for(final record in loadAll()){
      if(record.periodId==periodId &&
         record.candidateKey==evaluation.candidate.dedupeKey &&
          record.tierCode == tier &&
          record.officialPdfSha256.toLowerCase() == sha.toLowerCase()) {
        return record;
      }
    }
    return null;
  }

  Future<InvoiceAwardCloudEligibilityConfirmation> saveDecision({
    required String periodId,
    required ExistingInvoiceAwardCloudEvaluation evaluation,
    required InvoiceAwardCloudEligibilityUserDecision decision,
    required DateTime confirmedAtUtc,
  }) async {
    final tier=evaluation.selectedTierCode;
    final sha=evaluation.pdfSha256;
    // Fail before any preferences write; never delete old 500 audit records.
    if (tier != null &&
        Cloud500ProductionPolicy.blocksCloud500Persistence(tier)) {
      throw StateError(Cloud500ProductionPolicy.deferredCode);
    }
    if(evaluation.status!=
          ExistingInvoiceAwardCloudEvaluationStatus.matchedReviewRequired ||
       tier==null || evaluation.grossAmount<=0 || sha==null ||
       !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha)){
      throw StateError('CLOUD_ELIGIBILITY_CONFIRMATION_AUTHORITY_INVALID');
    }
    final record=InvoiceAwardCloudEligibilityConfirmation(
      periodId:periodId,
      candidateKey:evaluation.candidate.dedupeKey,
      candidateSourceProvenance:evaluation.candidate.sourceProvenance,
      tierCode:tier,
      grossAmount:evaluation.grossAmount,
      officialPdfSha256:sha.toLowerCase(),
      decision:decision,
      confirmedAtUtc:confirmedAtUtc.toUtc(),
    );
    if(!record.hasValidProvenance){
      throw StateError('CLOUD_ELIGIBILITY_CONFIRMATION_PROVENANCE_INVALID');
    }
    final values=loadAll().where((item)=>!(
      item.periodId==record.periodId && item.candidateKey==record.candidateKey &&
      item.tierCode==record.tierCode)).toList(growable:true)..add(record);
    values.sort((a,b)=>a.candidateKey.compareTo(b.candidateKey));
    await preferences.setString(_recordsKey,
      jsonEncode(values.map((item)=>item.toJson()).toList(growable:false)));
    return record;
  }
}
