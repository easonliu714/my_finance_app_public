import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_finance_app/features/invoice/existing_invoice_award_candidate_repository.dart';
import 'package:my_finance_app/features/invoice/existing_invoice_award_cloud_batch_matcher.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_eligibility_confirmation.dart';

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
