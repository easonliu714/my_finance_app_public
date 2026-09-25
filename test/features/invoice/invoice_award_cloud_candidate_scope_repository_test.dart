import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_candidate_scope.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_candidate_scope_repository.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_publication_parser.dart';

void main() {
  late Directory tempDir;
  late CloudAwardCandidateScopeRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'cloud_candidate_scope_repo_',
    );
    repository = CloudAwardCandidateScopeRepository(
      rootDirectoryProvider: () async => tempDir,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  const reference = OfficialCloudAwardArtifactReference(
    artifactId: '20260506_20260725124620_sorted_AI_D.pdf',
    sourceUri: Uri.parse(
      'https://invoice.etax.nat.gov.tw/pdf/'
      '20260506_20260725124620_sorted_AI_D.pdf',
    ),
    periodId: '115-05-06',
    tierCode: 'cloud-500',
  );

  Future<CloudAwardCandidateScopedAuthority> authority({
    Set<String> candidates = const <String>{'AB12345678', 'CD87654321'},
    Set<String> matches = const <String>{'CD87654321'},
  }) async {
    return CloudAwardCandidateScopedAuthority(
      periodId: reference.periodId,
      tierCode: reference.tierCode,
      officialSourceUri: reference.sourceUri,
      pdfSha256: 'a' * 64,
      candidateUniverseSha256: await cloudCandidateUniverseSha256(candidates),
      candidateNumbers: candidates,
      matchedInvoiceNumbers: matches,
    );
  }

  test('promote read-back reuses exact source PDF and candidate universe',
      () async {
    final promoted = await repository.promoteValidated(
      reference: reference,
      pdfSha256: 'a' * 64,
      authority: await authority(),
      verifiedAtUtc: DateTime.utc(2026, 9, 25, 2),
      retentionUntilUtc: DateTime.utc(2026, 11, 5, 15, 59, 59),
    );

    expect(promoted.matchedInvoiceNumbers, const <String>{'CD87654321'});

    final readBack = await repository.readValidated(
      reference: reference,
      pdfSha256: 'a' * 64,
      candidateInvoiceNumbers: const <String>[
        'cd87654321',
        'ab-12345678',
      ],
      nowUtc: DateTime.utc(2026, 9, 25, 3),
    );

    expect(readBack, isNotNull);
    expect(readBack!.candidateNumbers, const <String>{
      'AB12345678',
      'CD87654321',
    });
    expect(readBack.matchedInvoiceNumbers, const <String>{'CD87654321'});
  });

  test('candidate set or PDF SHA change invalidates durable authority', () async {
    await repository.promoteValidated(
      reference: reference,
      pdfSha256: 'a' * 64,
      authority: await authority(),
      verifiedAtUtc: DateTime.utc(2026, 9, 25, 2),
    );

    expect(
      await repository.readValidated(
        reference: reference,
        pdfSha256: 'a' * 64,
        candidateInvoiceNumbers: const <String>['AB12345678'],
      ),
      isNull,
    );
    expect(
      await repository.readValidated(
        reference: reference,
        pdfSha256: 'b' * 64,
        candidateInvoiceNumbers: const <String>[
          'AB12345678',
          'CD87654321',
        ],
      ),
      isNull,
    );
  });

  test('expired candidate authority is pruned and cannot be reused', () async {
    await repository.promoteValidated(
      reference: reference,
      pdfSha256: 'a' * 64,
      authority: await authority(),
      verifiedAtUtc: DateTime.utc(2026, 9, 25, 2),
      retentionUntilUtc: DateTime.utc(2026, 9, 25, 3),
    );

    expect(
      await repository.pruneExpired(
        nowUtc: DateTime.utc(2026, 9, 25, 4),
      ),
      1,
    );
    expect(
      await repository.readValidated(
        reference: reference,
        pdfSha256: 'a' * 64,
        candidateInvoiceNumbers: const <String>[
          'AB12345678',
          'CD87654321',
        ],
        nowUtc: DateTime.utc(2026, 9, 25, 4),
      ),
      isNull,
    );
  });
}
