import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/existing_invoice_award_candidate_repository.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_candidate_scope.dart';

void main() {
  test('candidate lookup cancellation is explicit and idempotent', () {
    final cancellation = CloudAwardCandidateLookupCancellation();
    expect(cancellation.isCancelled, isFalse);
    cancellation.cancel();
    cancellation.cancel();
    expect(cancellation.isCancelled, isTrue);
    expect(
      cancellation.throwIfCancelled,
      throwsA(isA<CloudAwardCandidateLookupCancelled>()),
    );
  });
  test('candidate universe normalization is exact and order independent',
      () async {
    final normalized = normalizeCloudCandidateNumbers(
      const <String>[
        'ab-12345678',
        'CD87654321',
        ' AB12345678 ',
        'bad',
      ],
    );

    expect(
      normalized,
      const <String>{'AB12345678', 'CD87654321'},
    );

    final first = await cloudCandidateUniverseSha256(
      const <String>['AB12345678', 'CD87654321'],
    );
    final second = await cloudCandidateUniverseSha256(
      const <String>['cd87654321', 'ab-12345678'],
    );

    expect(first, hasLength(64));
    expect(second, first);
  });

  test('candidate universe matches cloud matcher eligibility semantics', () {
    ExistingInvoiceAwardCandidate candidate({
      required String number,
      required ExistingInvoiceAwardIdentitySource source,
      required ExistingInvoiceAwardCloudEligibility eligibility,
      String awardPeriod = '115/06',
    }) =>
        ExistingInvoiceAwardCandidate(
          transactionId: 'tx-$number',
          invoiceNumber: number,
          invoiceDate: DateTime(2026, 6, 1),
          awardPeriod: awardPeriod,
          identitySource: source,
          sourceProvenance: 'fixture',
          cloudEligibility: eligibility,
        );

    final universe = cloudCandidateNumbersForAwardPeriod(
      candidates: <ExistingInvoiceAwardCandidate>[
        candidate(
          number: 'AB12345678',
          source: ExistingInvoiceAwardIdentitySource.cloudMetadata,
          eligibility: ExistingInvoiceAwardCloudEligibility.eligible,
        ),
        candidate(
          number: 'CD87654321',
          source: ExistingInvoiceAwardIdentitySource.cloudMetadata,
          eligibility:
              ExistingInvoiceAwardCloudEligibility.unknownReviewRequired,
        ),
        candidate(
          number: 'EF11112222',
          source: ExistingInvoiceAwardIdentitySource.cloudMetadata,
          eligibility: ExistingInvoiceAwardCloudEligibility.ineligible,
        ),
        candidate(
          number: 'GH33334444',
          source: ExistingInvoiceAwardIdentitySource.governedReviewNote,
          eligibility: ExistingInvoiceAwardCloudEligibility.eligible,
        ),
        candidate(
          number: 'IJ55556666',
          source: ExistingInvoiceAwardIdentitySource.cloudMetadata,
          eligibility: ExistingInvoiceAwardCloudEligibility.eligible,
          awardPeriod: '115/08',
        ),
      ],
      awardPeriod: '115/06',
    );

    expect(universe, const <String>{'AB12345678', 'CD87654321'});
  });

  test('candidate-scoped authority covers only the exact candidate universe',
      () {
    final authority = CloudAwardCandidateScopedAuthority(
      periodId: '115-05-06',
      tierCode: 'cloud-500',
      officialSourceUri: Uri.parse(
        'https://invoice.etax.nat.gov.tw/pdf/'
        '20260506_20260725124620_sorted_AI_D.pdf',
      ),
      pdfSha256: 'a' * 64,
      candidateUniverseSha256: 'b' * 64,
      candidateNumbers: const <String>{'AB12345678', 'CD87654321'},
      matchedInvoiceNumbers: const <String>{'CD87654321'},
    );

    expect(
      authority.covers(
        periodId: '115-05-06',
        tierCode: 'cloud-500',
        invoiceNumbers: const <String>['cd87654321', 'ab12345678'],
      ),
      isTrue,
    );
    expect(
      authority.covers(
        periodId: '115-05-06',
        tierCode: 'cloud-500',
        invoiceNumbers: const <String>['AB12345678'],
      ),
      isFalse,
    );
    expect(
      authority.covers(
        periodId: '115-07-08',
        tierCode: 'cloud-500',
        invoiceNumbers: const <String>['AB12345678', 'CD87654321'],
      ),
      isFalse,
    );
  });
}
