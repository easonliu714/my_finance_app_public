import 'package:shared_preferences/shared_preferences.dart';

import 'existing_invoice_award_cloud_batch_matcher.dart';
import 'existing_invoice_award_general_batch_matcher.dart';
import 'invoice_award_cloud_eligibility_confirmation.dart';
import 'invoice_award_official_dataset.dart';
import 'invoice_award_payout_bookkeeping_contract.dart';
import 'invoice_award_period_catalog.dart';

class InvoiceAwardPayoutBookkeepingSettings {
  const InvoiceAwardPayoutBookkeepingSettings({
    required this.automaticBookkeepingEnabled,
    required this.externalMofRemittanceConfigured,
    required this.localAccountId,
  });

  final bool automaticBookkeepingEnabled;
  final bool externalMofRemittanceConfigured;
  final String localAccountId;

  bool get hasDestinationAccount => localAccountId.trim().isNotEmpty;
}

class InvoiceAwardPayoutBookkeepingSettingsRepository {
  InvoiceAwardPayoutBookkeepingSettingsRepository(this.preferences);

  final SharedPreferences preferences;

  static const _enabledKey =
      'issue13_payout_bookkeeping_automatic_enabled_v1';
  static const _externalConfiguredKey =
      'issue13_payout_bookkeeping_external_mof_configured_v1';
  static const _accountIdKey =
      'issue13_payout_bookkeeping_local_account_id_v1';

  InvoiceAwardPayoutBookkeepingSettings load() =>
      InvoiceAwardPayoutBookkeepingSettings(
        automaticBookkeepingEnabled:
            preferences.getBool(_enabledKey) ?? false,
        externalMofRemittanceConfigured:
            preferences.getBool(_externalConfiguredKey) ?? false,
        localAccountId: preferences.getString(_accountIdKey) ?? '',
      );

  Future<void> save(InvoiceAwardPayoutBookkeepingSettings value) async {
    await preferences.setBool(
      _enabledKey,
      value.automaticBookkeepingEnabled,
    );
    await preferences.setBool(
      _externalConfiguredKey,
      value.externalMofRemittanceConfigured,
    );
    await preferences.setString(_accountIdKey, value.localAccountId.trim());
  }
}

enum InvoiceAwardPayoutBookkeepingReadinessStatus {
  disabled,
  destinationAccountMissing,
  externalRemittanceNotConfigured,
  officialAuthorityIncomplete,
  cloudEligibilityConfirmationRequired,
  beforeRedemptionStart,
  readyProposal,
}

class InvoiceAwardPayoutBookkeepingReadiness {
  const InvoiceAwardPayoutBookkeepingReadiness({
    required this.invoiceIdentity,
    required this.prizeTier,
    required this.grossAmount,
    required this.status,
    required this.externalRemittanceEligibleAt,
    this.proposal,
  });

  final String invoiceIdentity;
  final String prizeTier;
  final int grossAmount;
  final InvoiceAwardPayoutBookkeepingReadinessStatus status;
  final DateTime externalRemittanceEligibleAt;
  final InvoiceAwardPayoutBookkeepingProposal? proposal;

  bool get isReady =>
      status == InvoiceAwardPayoutBookkeepingReadinessStatus.readyProposal &&
      proposal != null;
}

class InvoiceAwardPayoutBookkeepingPlanner {
  const InvoiceAwardPayoutBookkeepingPlanner({
    this.builder = const InvoiceAwardPayoutBookkeepingProposalBuilder(),
  });

  final InvoiceAwardPayoutBookkeepingProposalBuilder builder;

  List<InvoiceAwardPayoutBookkeepingReadiness> evaluate({
    required InvoiceAwardSelectablePeriod period,
    required DateTime nowUtc,
    required InvoiceAwardPayoutBookkeepingSettings settings,
    required bool generalAuthorityComplete,
    required bool cloudAuthorityComplete,
    required OfficialInvoiceAwardDataset? generalDataset,
    required Iterable<ExistingInvoiceAwardGeneralEvaluation>
        generalEvaluations,
    required Iterable<ExistingInvoiceAwardCloudEvaluation> cloudEvaluations,
    required Map<String, InvoiceAwardCloudEligibilityConfirmation>
        cloudEligibilityConfirmations,
  }) {
    if (!nowUtc.isUtc) {
      return const <InvoiceAwardPayoutBookkeepingReadiness>[];
    }

    final generalByKey = <String, ExistingInvoiceAwardGeneralEvaluation>{
      for (final value in generalEvaluations)
        value.candidate.dedupeKey: value,
    };
    final cloudByKey = <String, ExistingInvoiceAwardCloudEvaluation>{
      for (final value in cloudEvaluations)
        value.candidate.dedupeKey: value,
    };
    final candidateKeys = <String>{
      ...generalByKey.keys,
      ...cloudByKey.keys,
    };
    final eligibleAt = _taipeiMidnightUtc(
      period.redemptionStartYear,
      period.redemptionStartMonth,
      period.redemptionStartDay,
    );
    final results = <InvoiceAwardPayoutBookkeepingReadiness>[];

    for (final candidateKey in candidateKeys) {
      final general = generalByKey[candidateKey];
      final cloud = cloudByKey[candidateKey];
      final selected = _selectPrize(
        candidateKey: candidateKey,
        general: general,
        cloud: cloud,
        cloudEligibilityConfirmations: cloudEligibilityConfirmations,
        generalDataset: generalDataset,
      );
      if (selected == null) {
        if (cloud?.status ==
            ExistingInvoiceAwardCloudEvaluationStatus.matchedReviewRequired) {
          results.add(
            InvoiceAwardPayoutBookkeepingReadiness(
              invoiceIdentity: candidateKey,
              prizeTier: cloud!.selectedTierCode ?? 'cloud-review',
              grossAmount: cloud.grossAmount,
              status: InvoiceAwardPayoutBookkeepingReadinessStatus
                  .cloudEligibilityConfirmationRequired,
              externalRemittanceEligibleAt: eligibleAt,
            ),
          );
        }
        continue;
      }

      final status = _blockingStatus(
        settings: settings,
        generalAuthorityComplete: generalAuthorityComplete,
        cloudAuthorityComplete: cloudAuthorityComplete,
        nowUtc: nowUtc,
        eligibleAt: eligibleAt,
      );
      if (status != null) {
        results.add(
          InvoiceAwardPayoutBookkeepingReadiness(
            invoiceIdentity: candidateKey,
            prizeTier: selected.prizeTier,
            grossAmount: selected.grossAmount,
            status: status,
            externalRemittanceEligibleAt: eligibleAt,
          ),
        );
        continue;
      }

      final candidate = InvoiceAwardPayoutBookkeepingProposal(
        invoiceIdentity: candidateKey,
        awardPeriodId: period.period.id,
        prizeTier: selected.prizeTier,
        grossAmount: selected.grossAmount,
        localAccountId: settings.localAccountId,
        externalRemittanceEligibleAt: eligibleAt,
        officialDatasetFingerprint: selected.fingerprint,
        parserRuleVersion: selected.parserRuleVersion,
      );
      final proposal = builder.build(
        candidate: candidate,
        now: nowUtc,
        explicitUserAuthorization: settings.automaticBookkeepingEnabled,
        externalMofRemittanceConfigured:
            settings.externalMofRemittanceConfigured,
      );
      results.add(
        InvoiceAwardPayoutBookkeepingReadiness(
          invoiceIdentity: candidateKey,
          prizeTier: selected.prizeTier,
          grossAmount: selected.grossAmount,
          status: proposal == null
              ? InvoiceAwardPayoutBookkeepingReadinessStatus
                  .officialAuthorityIncomplete
              : InvoiceAwardPayoutBookkeepingReadinessStatus.readyProposal,
          externalRemittanceEligibleAt: eligibleAt,
          proposal: proposal,
        ),
      );
    }

    results.sort((left, right) {
      final amount = right.grossAmount.compareTo(left.grossAmount);
      return amount != 0
          ? amount
          : left.invoiceIdentity.compareTo(right.invoiceIdentity);
    });
    return List<InvoiceAwardPayoutBookkeepingReadiness>.unmodifiable(results);
  }

  InvoiceAwardPayoutBookkeepingReadinessStatus? _blockingStatus({
    required InvoiceAwardPayoutBookkeepingSettings settings,
    required bool generalAuthorityComplete,
    required bool cloudAuthorityComplete,
    required DateTime nowUtc,
    required DateTime eligibleAt,
  }) {
    if (!settings.automaticBookkeepingEnabled) {
      return InvoiceAwardPayoutBookkeepingReadinessStatus.disabled;
    }
    if (!settings.hasDestinationAccount) {
      return InvoiceAwardPayoutBookkeepingReadinessStatus
          .destinationAccountMissing;
    }
    if (!settings.externalMofRemittanceConfigured) {
      return InvoiceAwardPayoutBookkeepingReadinessStatus
          .externalRemittanceNotConfigured;
    }
    if (!generalAuthorityComplete || !cloudAuthorityComplete) {
      return InvoiceAwardPayoutBookkeepingReadinessStatus
          .officialAuthorityIncomplete;
    }
    if (nowUtc.isBefore(eligibleAt)) {
      return InvoiceAwardPayoutBookkeepingReadinessStatus
          .beforeRedemptionStart;
    }
    return null;
  }

  _SelectedPrize? _selectPrize({
    required String candidateKey,
    required ExistingInvoiceAwardGeneralEvaluation? general,
    required ExistingInvoiceAwardCloudEvaluation? cloud,
    required Map<String, InvoiceAwardCloudEligibilityConfirmation>
        cloudEligibilityConfirmations,
    required OfficialInvoiceAwardDataset? generalDataset,
  }) {
    final options = <_SelectedPrize>[];

    if (general?.isWinner == true &&
        general!.grossAmount > 0 &&
        generalDataset != null &&
        RegExp(r'^[0-9a-fA-F]{64}$')
            .hasMatch(generalDataset.provenance.contentSha256) &&
        generalDataset.provenance.parserVersion.trim().isNotEmpty) {
      options.add(
        _SelectedPrize(
          prizeTier: 'general-${general.matchKind.name}',
          grossAmount: general.grossAmount,
          fingerprint: generalDataset.provenance.contentSha256,
          parserRuleVersion: generalDataset.provenance.parserVersion,
        ),
      );
    }

    if (cloud?.hasCloudNumberMatch == true &&
        cloud!.grossAmount > 0 &&
        cloud.selectedTierCode != null &&
        cloud.pdfSha256 != null &&
        RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(cloud.pdfSha256!)) {
      var cloudEligible = cloud.isConfirmedCloudNumberMatch;
      if (cloud.status ==
          ExistingInvoiceAwardCloudEvaluationStatus.matchedReviewRequired) {
        final confirmation = cloudEligibilityConfirmations[
            _cloudEligibilityConfirmationKey(cloud)];
        cloudEligible = confirmation?.confirmsEligibility == true;
      }
      if (cloudEligible) {
        options.add(
          _SelectedPrize(
            prizeTier: cloud.selectedTierCode!,
            grossAmount: cloud.grossAmount,
            fingerprint: cloud.pdfSha256!,
            parserRuleVersion: 'issue13-cloud-candidate-authority-v1',
          ),
        );
      }
    }

    if (options.isEmpty) return null;
    options.sort((left, right) {
      final amount = right.grossAmount.compareTo(left.grossAmount);
      return amount != 0
          ? amount
          : left.prizeTier.compareTo(right.prizeTier);
    });
    return options.first;
  }
}

class _SelectedPrize {
  const _SelectedPrize({
    required this.prizeTier,
    required this.grossAmount,
    required this.fingerprint,
    required this.parserRuleVersion,
  });

  final String prizeTier;
  final int grossAmount;
  final String fingerprint;
  final String parserRuleVersion;
}

String _cloudEligibilityConfirmationKey(
  ExistingInvoiceAwardCloudEvaluation evaluation,
) =>
    '${evaluation.candidate.dedupeKey}|${evaluation.selectedTierCode ?? ''}';

DateTime _taipeiMidnightUtc(int year, int month, int day) =>
    DateTime.utc(year, month, day).subtract(const Duration(hours: 8));
