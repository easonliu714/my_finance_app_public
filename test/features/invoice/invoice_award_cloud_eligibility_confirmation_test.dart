import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_finance_app/features/invoice/existing_invoice_award_candidate_repository.dart';
import 'package:my_finance_app/features/invoice/existing_invoice_award_cloud_batch_matcher.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_eligibility_confirmation.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud500_production_policy.dart';

void main() {
  setUp(() { SharedPreferences.setMockInitialValues(<String, Object>{}); });

  ExistingInvoiceAwardCloudEvaluation evaluation() {
    final candidate = ExistingInvoiceAwardCandidate(
      transactionId: 'txn-cloud-review',
      invoiceNumber: 'BM23888900',
      invoiceDate: DateTime(2026, 6, 30),
      awardPeriod: '115/06',
      identitySource: ExistingInvoiceAwardIdentitySource.cloudMetadata,
      sourceProvenance: 'cloud_invoice_metadata_links:test',
      cloudEligibility: ExistingInvoiceAwardCloudEligibility.unknownReviewRequired,
    );
    return ExistingInvoiceAwardCloudEvaluation(
      candidate: candidate,
      status: ExistingInvoiceAwardCloudEvaluationStatus.matchedReviewRequired,
      missingTierCodes: const <String>{},
      matchedTierCodes: const <String>{'cloud-500'},
      selectedTierCode: 'cloud-500',
      grossAmount: 500,
      pdfSha256:
          'f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571',
    );
  }

  test('eligible decision persists with exact source provenance', () async {
    final preferences = await SharedPreferences.getInstance();
    final repository =
        InvoiceAwardCloudEligibilityConfirmationRepository(preferences);
    final value = evaluation();
    final record = await repository.saveDecision(
      periodId: '115-05-06',
      evaluation: value,
      decision: InvoiceAwardCloudEligibilityUserDecision.eligible,
      confirmedAtUtc: DateTime.utc(2026, 10, 6, 8),
    );
    expect(record.confirmsEligibility, isTrue);
    expect(record.canAuthorizeFutureBookkeepingEligibility, isTrue);
    final readBack = repository.readForEvaluation(
      periodId: '115-05-06', evaluation: value);
    expect(readBack?.confirmsEligibility, isTrue);
    expect(readBack?.officialPdfSha256, value.pdfSha256);
  });


  test('Owner C release cannot authorize historic 500 consent; other tiers survive', () async {
    final preferences = await SharedPreferences.getInstance();
    final repository =
        InvoiceAwardCloudEligibilityConfirmationRepository(preferences);
    final legacy = evaluation();
    final legacyRecord = await repository.saveDecision(
      periodId: '115-05-06',
      evaluation: legacy,
      decision: InvoiceAwardCloudEligibilityUserDecision.eligible,
      confirmedAtUtc: DateTime.utc(2026, 10, 6, 8),
    );
    // Test both release and diagnostic policy decisions without exposing a
    // caller-supplied build-mode override on the production model.
    expect(
      Cloud500ProductionPolicy.blocksCloud500PersistenceForBuild(
        tierCode: 'cloud-500',
        isReleaseBuild: true,
      ),
      isTrue,
    );
    expect(
      Cloud500ProductionPolicy.blocksCloud500PersistenceForBuild(
        tierCode: 'cloud-500',
        isReleaseBuild: false,
      ),
      isFalse,
    );
    expect(legacyRecord.confirmsEligibility, !kReleaseMode);
    expect(legacyRecord.canAuthorizeFutureBookkeepingEligibility, !kReleaseMode);

    final otherTier = ExistingInvoiceAwardCloudEvaluation(
      candidate: legacy.candidate,
      status: ExistingInvoiceAwardCloudEvaluationStatus.matchedReviewRequired,
      missingTierCodes: const <String>{},
      matchedTierCodes: const <String>{'cloud-800'},
      selectedTierCode: 'cloud-800',
      grossAmount: 800,
      pdfSha256: List<String>.filled(64, 'a').join(),
    );
    final otherRecord = await repository.saveDecision(
      periodId: '115-05-06',
      evaluation: otherTier,
      decision: InvoiceAwardCloudEligibilityUserDecision.eligible,
      confirmedAtUtc: DateTime.utc(2026, 10, 6, 9),
    );
    expect(
      Cloud500ProductionPolicy.blocksCloud500PersistenceForBuild(
        tierCode: 'cloud-800',
        isReleaseBuild: true,
      ),
      isFalse,
    );
    expect(otherRecord.canAuthorizeFutureBookkeepingEligibility, isTrue);
    // Saving another tier must not prune the old 500 evidence from storage.
    expect(
      repository.loadAll().map((item) => item.tierCode).toSet(),
      <String>{'cloud-500', 'cloud-800'},
    );
    expect(
      repository.readForEvaluation(
        periodId: '115-05-06',
        evaluation: legacy,
      ),
      kReleaseMode ? isNull : isNotNull,
    );
    expect(
      repository.readForEvaluation(
        periodId: '115-05-06',
        evaluation: otherTier,
      ),
      isNotNull,
    );
  });

  test('ineligible decision cannot authorize future bookkeeping', () async {
    final preferences = await SharedPreferences.getInstance();
    final repository =
        InvoiceAwardCloudEligibilityConfirmationRepository(preferences);
    final value = evaluation();
    final record = await repository.saveDecision(
      periodId: '115-05-06',
      evaluation: value,
      decision: InvoiceAwardCloudEligibilityUserDecision.ineligible,
      confirmedAtUtc: DateTime.utc(2026, 10, 6, 8),
    );
    expect(record.confirmsIneligibility, isTrue);
    expect(record.canAuthorizeFutureBookkeepingEligibility, isFalse);
  });
}
