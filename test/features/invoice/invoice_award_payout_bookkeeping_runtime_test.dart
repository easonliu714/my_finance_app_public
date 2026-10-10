import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_finance_app/features/invoice/existing_invoice_award_candidate_repository.dart';
import 'package:my_finance_app/features/invoice/existing_invoice_award_cloud_batch_matcher.dart';
import 'package:my_finance_app/features/invoice/existing_invoice_award_general_batch_matcher.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_eligibility_confirmation.dart';
import 'package:my_finance_app/features/invoice/invoice_award_official_dataset.dart';
import 'package:my_finance_app/features/invoice/invoice_award_payout_bookkeeping_runtime.dart';
import 'package:my_finance_app/features/invoice/invoice_award_period_catalog.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('settings persist automatic bookkeeping preflight choices', () async {
    final preferences = await SharedPreferences.getInstance();
    final repository =
        InvoiceAwardPayoutBookkeepingSettingsRepository(preferences);
    const value = InvoiceAwardPayoutBookkeepingSettings(
      automaticBookkeepingEnabled: true,
      externalMofRemittanceConfigured: true,
      localAccountId: 'bank-1',
    );

    await repository.save(value);
    final readBack = repository.load();

    expect(readBack.automaticBookkeepingEnabled, isTrue);
    expect(readBack.externalMofRemittanceConfigured, isTrue);
    expect(readBack.localAccountId, 'bank-1');
  });

  test('general winner becomes a read-only proposal after redemption starts',
      () {
    const planner = InvoiceAwardPayoutBookkeepingPlanner();
    final candidate = _candidate();
    final result = planner.evaluate(
      period: InvoiceAwardRecentPeriodCatalog.period1150708,
      nowUtc: DateTime.utc(2026, 10, 6),
      settings: const InvoiceAwardPayoutBookkeepingSettings(
        automaticBookkeepingEnabled: true,
        externalMofRemittanceConfigured: true,
        localAccountId: 'bank-1',
      ),
      generalAuthorityComplete: true,
      cloudAuthorityComplete: true,
      generalDataset: _dataset(),
      generalEvaluations: <ExistingInvoiceAwardGeneralEvaluation>[
        ExistingInvoiceAwardGeneralEvaluation(
          candidate: candidate,
          status: ExistingInvoiceAwardGeneralEvaluationStatus.winner,
          matchKind: OfficialInvoiceAwardMatchKind.sixth,
        ),
      ],
      cloudEvaluations: const <ExistingInvoiceAwardCloudEvaluation>[],
      cloudEligibilityConfirmations:
          const <String, InvoiceAwardCloudEligibilityConfirmation>{},
    );

    expect(result, hasLength(1));
    expect(result.single.status,
        InvoiceAwardPayoutBookkeepingReadinessStatus.readyProposal);
    expect(result.single.proposal?.grossAmount, 200);
    expect(result.single.proposal?.canCreateFormalTransaction, isFalse);
  });

  test('cloud review winner requires persisted eligible confirmation', () {
    const planner = InvoiceAwardPayoutBookkeepingPlanner();
    final candidate = _candidate(cloud: true);
    final cloud = ExistingInvoiceAwardCloudEvaluation(
      candidate: candidate,
      status:
          ExistingInvoiceAwardCloudEvaluationStatus.matchedReviewRequired,
      missingTierCodes: const <String>{},
      matchedTierCodes: const <String>{'cloud-500'},
      selectedTierCode: 'cloud-500',
      grossAmount: 500,
      pdfSha256:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );

    final blocked = planner.evaluate(
      period: InvoiceAwardRecentPeriodCatalog.period1150506,
      nowUtc: DateTime.utc(2026, 10, 7),
      settings: const InvoiceAwardPayoutBookkeepingSettings(
        automaticBookkeepingEnabled: true,
        externalMofRemittanceConfigured: true,
        localAccountId: 'bank-1',
      ),
      generalAuthorityComplete: true,
      cloudAuthorityComplete: true,
      generalDataset: _dataset(period:
          const OfficialInvoiceAwardPeriod(
              rocYear: 115, startMonth: 5, endMonth: 6)),
      generalEvaluations: const <ExistingInvoiceAwardGeneralEvaluation>[],
      cloudEvaluations: <ExistingInvoiceAwardCloudEvaluation>[cloud],
      cloudEligibilityConfirmations:
          const <String, InvoiceAwardCloudEligibilityConfirmation>{},
    );
    expect(blocked.single.status,
        InvoiceAwardPayoutBookkeepingReadinessStatus
            .cloudEligibilityConfirmationRequired);

    final confirmation = InvoiceAwardCloudEligibilityConfirmation(
      periodId: '115-05-06',
      candidateKey: candidate.dedupeKey,
      candidateSourceProvenance: candidate.sourceProvenance,
      tierCode: 'cloud-500',
      grossAmount: 500,
      officialPdfSha256: cloud.pdfSha256!,
      decision: InvoiceAwardCloudEligibilityUserDecision.eligible,
      confirmedAtUtc: DateTime.utc(2026, 10, 7),
    );
    final ready = planner.evaluate(
      period: InvoiceAwardRecentPeriodCatalog.period1150506,
      nowUtc: DateTime.utc(2026, 10, 7),
      settings: const InvoiceAwardPayoutBookkeepingSettings(
        automaticBookkeepingEnabled: true,
        externalMofRemittanceConfigured: true,
        localAccountId: 'bank-1',
      ),
      generalAuthorityComplete: true,
      cloudAuthorityComplete: true,
      generalDataset: _dataset(period:
          const OfficialInvoiceAwardPeriod(
              rocYear: 115, startMonth: 5, endMonth: 6)),
      generalEvaluations: const <ExistingInvoiceAwardGeneralEvaluation>[],
      cloudEvaluations: <ExistingInvoiceAwardCloudEvaluation>[cloud],
      cloudEligibilityConfirmations: <String,
          InvoiceAwardCloudEligibilityConfirmation>{
        '${candidate.dedupeKey}|cloud-500': confirmation,
      },
    );

    expect(ready.single.status,
        InvoiceAwardPayoutBookkeepingReadinessStatus.readyProposal);
    expect(ready.single.proposal?.grossAmount, 500);
  });

  test('preflight fails closed when external remittance is not configured', () {
    const planner = InvoiceAwardPayoutBookkeepingPlanner();
    final candidate = _candidate();
    final result = planner.evaluate(
      period: InvoiceAwardRecentPeriodCatalog.period1150708,
      nowUtc: DateTime.utc(2026, 10, 7),
      settings: const InvoiceAwardPayoutBookkeepingSettings(
        automaticBookkeepingEnabled: true,
        externalMofRemittanceConfigured: false,
        localAccountId: 'bank-1',
      ),
      generalAuthorityComplete: true,
      cloudAuthorityComplete: true,
      generalDataset: _dataset(),
      generalEvaluations: <ExistingInvoiceAwardGeneralEvaluation>[
        ExistingInvoiceAwardGeneralEvaluation(
          candidate: candidate,
          status: ExistingInvoiceAwardGeneralEvaluationStatus.winner,
          matchKind: OfficialInvoiceAwardMatchKind.sixth,
        ),
      ],
      cloudEvaluations: const <ExistingInvoiceAwardCloudEvaluation>[],
      cloudEligibilityConfirmations:
          const <String, InvoiceAwardCloudEligibilityConfirmation>{},
    );

    expect(result.single.status,
        InvoiceAwardPayoutBookkeepingReadinessStatus
            .externalRemittanceNotConfigured);
    expect(result.single.proposal, isNull);
  });
}

ExistingInvoiceAwardCandidate _candidate({bool cloud = false}) =>
    ExistingInvoiceAwardCandidate(
      transactionId: 'tx-1',
      invoiceNumber: cloud ? 'BM23888900' : 'CR30912111',
      invoiceDate: DateTime(2026, cloud ? 6 : 8, 15),
      awardPeriod: cloud ? '115/06' : '115/08',
      identitySource: cloud
          ? ExistingInvoiceAwardIdentitySource.cloudMetadata
          : ExistingInvoiceAwardIdentitySource.governedReviewNote,
      sourceProvenance: cloud
          ? 'cloud_invoice_metadata_links:test'
          : GovernedInvoiceReviewNoteParser.sourceMarker,
      cloudEligibility: cloud
          ? ExistingInvoiceAwardCloudEligibility.unknownReviewRequired
          : ExistingInvoiceAwardCloudEligibility.ineligible,
    );

OfficialInvoiceAwardDataset _dataset({
  OfficialInvoiceAwardPeriod period =
      const OfficialInvoiceAwardPeriod(
        rocYear: 115, startMonth: 7, endMonth: 8),
}) =>
    OfficialInvoiceAwardDataset(
      period: period,
      provenance: OfficialInvoiceAwardProvenance(
        sourceId: OfficialInvoiceAwardProvenance.ministryOfFinanceSourceId,
        fetchedAt: DateTime.utc(2026, 9, 25),
        parserVersion: 'test-parser-v1',
        contentSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      rules: const <OfficialInvoiceAwardRule>[
        OfficialInvoiceAwardRule(
            kind: OfficialInvoiceAwardRuleKind.special,
            number: '11111111'),
        OfficialInvoiceAwardRule(
            kind: OfficialInvoiceAwardRuleKind.grand,
            number: '22222222'),
        OfficialInvoiceAwardRule(
            kind: OfficialInvoiceAwardRuleKind.first,
            number: '33333333'),
      ],
      published: true,
      complete: true,
    );
