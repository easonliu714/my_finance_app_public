import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/existing_invoice_award_candidate_repository.dart';
import 'package:my_finance_app/features/invoice/existing_invoice_award_cloud_batch_matcher.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_candidate_scope.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_index_lkg_repository.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_pdf_index.dart';

void main() {
  late Directory tempDir;
  late Map<String, CloudAwardValidatedIndexSnapshot> snapshots;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cloud_batch_matcher_');
    snapshots = <String, CloudAwardValidatedIndexSnapshot>{};
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> addTier(
    String tier,
    List<String> numbers, {
    String periodId = '115-07-08',
  }) async {
    final index = File('${tempDir.path}/$periodId-$tier.index')
      ..writeAsStringSync('${numbers.join('\n')}\n');
    final manifestFile = File('${tempDir.path}/$periodId-$tier.json')
      ..writeAsStringSync('{}');
    snapshots['$periodId|$tier'] = CloudAwardValidatedIndexSnapshot(
      indexFile: index,
      manifestFile: manifestFile,
      manifest: CloudAwardLocalIndexManifest(
        periodId: periodId,
        tierCode: tier,
        officialSourceUri: Uri.parse(
          'https://invoice.etax.nat.gov.tw/pdf/fixture_sorted_AI_X.pdf',
        ),
        pdfSha256: _shaChar(tier, 'a') * 64,
        indexSha256: _shaChar(tier, 'b') * 64,
        extractorVersion: 'fixture-v1',
        rowCount: numbers.length,
        builtAt: DateTime.utc(2026, 9, 25, 7),
      ),
    );
  }

  Future<void> addAllTiers({
    String? million,
    String? twoThousand,
    String? eightHundred,
    String? fiveHundred,
  }) async {
    // A validated Cloud LKG index can never be empty. Use legal non-matching
    // fixture numbers for tiers that are present but do not contain the
    // candidate under test.
    await addTier(
      'cloud-1000000',
      <String>[million ?? 'ZX00000001'],
    );
    await addTier(
      'cloud-2000',
      <String>[twoThousand ?? 'ZX00000002'],
    );
    await addTier(
      'cloud-800',
      <String>[eightHundred ?? 'ZX00000003'],
    );
    await addTier(
      'cloud-500',
      <String>[fiveHundred ?? 'ZX00000004'],
    );
  }

  ExistingInvoiceAwardCandidate candidate({
    String invoiceNumber = 'AB12345678',
    ExistingInvoiceAwardIdentitySource source =
        ExistingInvoiceAwardIdentitySource.cloudMetadata,
    ExistingInvoiceAwardCloudEligibility eligibility =
        ExistingInvoiceAwardCloudEligibility.eligible,
    String awardPeriod = '115/08',
  }) =>
      ExistingInvoiceAwardCandidate(
        transactionId: 'tx-$invoiceNumber',
        invoiceNumber: invoiceNumber,
        invoiceDate: DateTime(2026, 8, 10),
        awardPeriod: awardPeriod,
        identitySource: source,
        sourceProvenance: 'fixture',
        cloudEligibility: eligibility,
      );

  ExistingInvoiceAwardCloudBatchMatcher matcher() =>
      ExistingInvoiceAwardCloudBatchMatcher(
        readLatest: ({
          required String periodId,
          required String tierCode,
        }) async =>
            snapshots['$periodId|$tierCode'],
      );

  test('eligible cloud invoice gets confirmed second-chance tier match',
      () async {
    await addAllTiers(eightHundred: 'AB12345678');

    final result = (await matcher().evaluate(
      candidates: <ExistingInvoiceAwardCandidate>[candidate()],
    ))
        .single;

    expect(
      result.status,
      ExistingInvoiceAwardCloudEvaluationStatus.matchedEligible,
    );
    expect(result.selectedTierCode, 'cloud-800');
    expect(result.grossAmount, 800);
    expect(result.hasCompleteAuthority, isTrue);
    expect(result.isConfirmedCloudNumberMatch, isTrue);
  });

  test('eligible cloud invoice with complete authority can be not matched',
      () async {
    await addAllTiers();

    final result = (await matcher().evaluate(
      candidates: <ExistingInvoiceAwardCandidate>[candidate()],
    ))
        .single;

    expect(
      result.status,
      ExistingInvoiceAwardCloudEvaluationStatus.notMatched,
    );
    expect(result.grossAmount, 0);
  });

  test('unknown eligibility preserves number match as review required',
      () async {
    await addAllTiers(fiveHundred: 'AB12345678');

    final result = (await matcher().evaluate(
      candidates: <ExistingInvoiceAwardCandidate>[
        candidate(
          eligibility:
              ExistingInvoiceAwardCloudEligibility.unknownReviewRequired,
        ),
      ],
    ))
        .single;

    expect(
      result.status,
      ExistingInvoiceAwardCloudEvaluationStatus.matchedReviewRequired,
    );
    expect(result.selectedTierCode, 'cloud-500');
    expect(result.grossAmount, 500);
    expect(result.isConfirmedCloudNumberMatch, isFalse);
    expect(result.requiresReview, isTrue);
  });

  test('ineligible and non-cloud candidates do not receive second chance',
      () async {
    await addAllTiers(million: 'AB12345678');

    final results = await matcher().evaluate(
      candidates: <ExistingInvoiceAwardCandidate>[
        candidate(eligibility: ExistingInvoiceAwardCloudEligibility.ineligible),
        candidate(
          invoiceNumber: 'CD87654321',
          source: ExistingInvoiceAwardIdentitySource.governedReviewNote,
          eligibility: ExistingInvoiceAwardCloudEligibility.ineligible,
        ),
      ],
    );

    expect(
      results[0].status,
      ExistingInvoiceAwardCloudEvaluationStatus.ineligible,
    );
    expect(
      results[1].status,
      ExistingInvoiceAwardCloudEvaluationStatus.notApplicable,
    );
  });

  test('missing tier authority prevents a definitive cloud conclusion',
      () async {
    await addTier('cloud-1000000', const <String>['ZX00000001']);
    await addTier('cloud-2000', const <String>['ZX00000002']);
    await addTier('cloud-800', const <String>['AB12345678']);

    final result = (await matcher().evaluate(
      candidates: <ExistingInvoiceAwardCandidate>[candidate()],
    ))
        .single;

    expect(
      result.status,
      ExistingInvoiceAwardCloudEvaluationStatus.authorityIncomplete,
    );
    expect(result.selectedTierCode, 'cloud-800');
    expect(result.missingTierCodes, contains('cloud-500'));
    expect(result.isConfirmedCloudNumberMatch, isFalse);
  });

  test('candidate-scoped 500 authority closes the missing-tier gap', () async {
    await addTier('cloud-1000000', const <String>['ZX00000001']);
    await addTier('cloud-2000', const <String>['ZX00000002']);
    await addTier('cloud-800', const <String>['ZX00000003']);

    final scoped = CloudAwardCandidateScopedAuthority(
      periodId: '115-07-08',
      tierCode: 'cloud-500',
      officialSourceUri: Uri.parse(
        'https://invoice.etax.nat.gov.tw/pdf/fixture_sorted_AI_D.pdf',
      ),
      pdfSha256: 'a' * 64,
      candidateUniverseSha256: 'c' * 64,
      candidateNumbers: const <String>{'AB12345678'},
      matchedInvoiceNumbers: const <String>{},
    );

    final result = (await matcher().evaluate(
      candidates: <ExistingInvoiceAwardCandidate>[candidate()],
      candidateScopedAuthorities: <CloudAwardCandidateScopedAuthority>[scoped],
    ))
        .single;

    expect(result.status, ExistingInvoiceAwardCloudEvaluationStatus.notMatched);
    expect(result.missingTierCodes, isEmpty);
    expect(result.hasCompleteAuthority, isTrue);
  });

  test('candidate-scoped 500 match remains eligible and exact-set bound',
      () async {
    await addTier('cloud-1000000', const <String>['ZX00000001']);
    await addTier('cloud-2000', const <String>['ZX00000002']);
    await addTier('cloud-800', const <String>['ZX00000003']);

    final scoped = CloudAwardCandidateScopedAuthority(
      periodId: '115-07-08',
      tierCode: 'cloud-500',
      officialSourceUri: Uri.parse(
        'https://invoice.etax.nat.gov.tw/pdf/fixture_sorted_AI_D.pdf',
      ),
      pdfSha256: 'a' * 64,
      candidateUniverseSha256: 'd' * 64,
      candidateNumbers: const <String>{'AB12345678'},
      matchedInvoiceNumbers: const <String>{'AB12345678'},
    );

    final result = (await matcher().evaluate(
      candidates: <ExistingInvoiceAwardCandidate>[candidate()],
      candidateScopedAuthorities: <CloudAwardCandidateScopedAuthority>[scoped],
    ))
        .single;

    expect(
      result.status,
      ExistingInvoiceAwardCloudEvaluationStatus.matchedEligible,
    );
    expect(result.selectedTierCode, 'cloud-500');
    expect(result.grossAmount, 500);

    final changedUniverse = await matcher().evaluate(
      candidates: <ExistingInvoiceAwardCandidate>[
        candidate(),
        candidate(invoiceNumber: 'CD87654321'),
      ],
      candidateScopedAuthorities: <CloudAwardCandidateScopedAuthority>[scoped],
    );
    expect(
      changedUniverse.first.status,
      ExistingInvoiceAwardCloudEvaluationStatus.authorityIncomplete,
    );
    expect(changedUniverse.first.missingTierCodes, contains('cloud-500'));
  });

  test('multiple tier hits select highest amount and force anomaly review',
      () async {
    await addAllTiers(
      million: 'AB12345678',
      fiveHundred: 'AB12345678',
    );

    final result = (await matcher().evaluate(
      candidates: <ExistingInvoiceAwardCandidate>[candidate()],
    ))
        .single;

    expect(
      result.status,
      ExistingInvoiceAwardCloudEvaluationStatus.anomalyReviewRequired,
    );
    expect(result.selectedTierCode, 'cloud-1000000');
    expect(result.grossAmount, 1000000);
    expect(result.matchedTierCodes, hasLength(2));
  });

  test('award period is isolated and invalid end-month fails closed', () async {
    await addAllTiers(eightHundred: 'AB12345678');

    final wrongPeriod = (await matcher().evaluate(
      candidates: <ExistingInvoiceAwardCandidate>[
        candidate(awardPeriod: '115/06'),
      ],
    ))
        .single;
    expect(
      wrongPeriod.status,
      ExistingInvoiceAwardCloudEvaluationStatus.authorityIncomplete,
    );
    expect(wrongPeriod.missingTierCodes, hasLength(4));

    final invalidPeriod = (await matcher().evaluate(
      candidates: <ExistingInvoiceAwardCandidate>[
        candidate(awardPeriod: '115/07'),
      ],
    ))
        .single;
    expect(
      invalidPeriod.status,
      ExistingInvoiceAwardCloudEvaluationStatus.invalidPeriod,
    );
  });
}

String _shaChar(String tier, String fallback) {
  final digit = tier.codeUnits.fold<int>(0, (value, item) => value + item) % 16;
  return digit.toRadixString(16).isEmpty ? fallback : digit.toRadixString(16);
}