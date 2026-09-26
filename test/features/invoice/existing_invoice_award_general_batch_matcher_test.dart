import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/existing_invoice_award_candidate_repository.dart';
import 'package:my_finance_app/features/invoice/existing_invoice_award_general_batch_matcher.dart';
import 'package:my_finance_app/features/invoice/invoice_award_official_dataset.dart';

void main() {
  const matcher = ExistingInvoiceAwardGeneralBatchMatcher();
  final dataset = OfficialInvoiceAwardDataset(
    period: const OfficialInvoiceAwardPeriod(
      rocYear: 115,
      startMonth: 7,
      endMonth: 8,
    ),
    provenance: OfficialInvoiceAwardProvenance(
      sourceId: OfficialInvoiceAwardProvenance.ministryOfFinanceSourceId,
      fetchedAt: DateTime.utc(2026, 9, 25, 6),
      parserVersion: 'fixture-v1',
      contentSha256: 'a' * 64,
    ),
    rules: const <OfficialInvoiceAwardRule>[
      OfficialInvoiceAwardRule(
        kind: OfficialInvoiceAwardRuleKind.special,
        number: '12345678',
      ),
      OfficialInvoiceAwardRule(
        kind: OfficialInvoiceAwardRuleKind.grand,
        number: '87654321',
      ),
      OfficialInvoiceAwardRule(
        kind: OfficialInvoiceAwardRuleKind.first,
        number: '11112222',
      ),
    ],
    published: true,
    complete: true,
  );

  ExistingInvoiceAwardCandidate candidate({
    required String transactionId,
    required String invoiceNumber,
    required DateTime invoiceDate,
    ExistingInvoiceAwardIdentitySource source =
        ExistingInvoiceAwardIdentitySource.governedReviewNote,
    ExistingInvoiceAwardCloudEligibility cloudEligibility =
        ExistingInvoiceAwardCloudEligibility.ineligible,
  }) {
    return ExistingInvoiceAwardCandidate(
      transactionId: transactionId,
      invoiceNumber: invoiceNumber,
      invoiceDate: invoiceDate,
      awardPeriod: '115/08',
      identitySource: source,
      sourceProvenance: 'fixture',
      cloudEligibility: cloudEligibility,
    );
  }

  test('batch-matches existing governed transactions against general awards', () {
    final results = matcher.evaluate(
      dataset: dataset,
      candidates: <ExistingInvoiceAwardCandidate>[
        candidate(
          transactionId: 't-special',
          invoiceNumber: 'AB12345678',
          invoiceDate: DateTime(2026, 8, 10),
        ),
        candidate(
          transactionId: 't-sixth',
          invoiceNumber: 'CD99999222',
          invoiceDate: DateTime(2026, 7, 3),
        ),
        candidate(
          transactionId: 't-no',
          invoiceNumber: 'EF00000001',
          invoiceDate: DateTime(2026, 8, 4),
        ),
      ],
    );

    expect(results, hasLength(3));
    expect(results[0].matchKind, OfficialInvoiceAwardMatchKind.special);
    expect(results[0].grossAmount, 10000000);
    expect(results[1].matchKind, OfficialInvoiceAwardMatchKind.sixth);
    expect(results[1].grossAmount, 200);
    expect(
      results[2].status,
      ExistingInvoiceAwardGeneralEvaluationStatus.notMatched,
    );
  });

  test('cloud-origin transaction still receives general-award evaluation', () {
    final results = matcher.evaluate(
      dataset: dataset,
      candidates: <ExistingInvoiceAwardCandidate>[
        candidate(
          transactionId: 'cloud-1',
          invoiceNumber: 'ZZ87654321',
          invoiceDate: DateTime(2026, 8, 1),
          source: ExistingInvoiceAwardIdentitySource.cloudMetadata,
          cloudEligibility:
              ExistingInvoiceAwardCloudEligibility.unknownReviewRequired,
        ),
      ],
    );

    expect(results.single.matchKind, OfficialInvoiceAwardMatchKind.grand);
    expect(results.single.isWinner, isTrue);
  });

  test('different award period is explicitly excluded from current dataset', () {
    final results = matcher.evaluate(
      dataset: dataset,
      candidates: <ExistingInvoiceAwardCandidate>[
        candidate(
          transactionId: 'old-1',
          invoiceNumber: 'AB12345678',
          invoiceDate: DateTime(2026, 6, 30),
        ),
      ],
    );

    expect(
      results.single.status,
      ExistingInvoiceAwardGeneralEvaluationStatus.outOfPeriod,
    );
  });
}
