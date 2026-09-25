import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_candidate_scope.dart';

void main() {
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
