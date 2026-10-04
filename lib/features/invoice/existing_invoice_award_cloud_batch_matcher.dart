import 'existing_invoice_award_candidate_repository.dart';
import 'invoice_award_cloud_candidate_scope.dart';
import 'invoice_award_cloud_index_lkg_repository.dart';
import 'invoice_award_cloud_pdf_index.dart';

typedef CloudAwardLatestSnapshotReader = Future<
    CloudAwardValidatedIndexSnapshot?> Function({
  required String periodId,
  required String tierCode,
});

enum ExistingInvoiceAwardCloudEvaluationStatus {
  notApplicable,
  ineligible,
  invalidPeriod,
  authorityIncomplete,
  notMatched,
  matchedEligible,
  matchedReviewRequired,
  anomalyReviewRequired,
}

class ExistingInvoiceAwardCloudEvaluation {
  const ExistingInvoiceAwardCloudEvaluation({
    required this.candidate,
    required this.status,
    required this.missingTierCodes,
    required this.matchedTierCodes,
    this.selectedTierCode,
    this.grossAmount = 0,
    this.indexSha256,
    this.pdfSha256,
  });

  final ExistingInvoiceAwardCandidate candidate;
  final ExistingInvoiceAwardCloudEvaluationStatus status;
  final Set<String> missingTierCodes;
  final Set<String> matchedTierCodes;
  final String? selectedTierCode;
  final int grossAmount;
  final String? indexSha256;
  final String? pdfSha256;

  bool get hasCloudNumberMatch => selectedTierCode != null;

  bool get hasCompleteAuthority => missingTierCodes.isEmpty;

  bool get isConfirmedCloudNumberMatch =>
      status == ExistingInvoiceAwardCloudEvaluationStatus.matchedEligible;

  bool get requiresReview =>
      status == ExistingInvoiceAwardCloudEvaluationStatus.authorityIncomplete ||
      status == ExistingInvoiceAwardCloudEvaluationStatus.matchedReviewRequired ||
      status == ExistingInvoiceAwardCloudEvaluationStatus.anomalyReviewRequired ||
      status == ExistingInvoiceAwardCloudEvaluationStatus.invalidPeriod;
}

/// Second-chance cloud-exclusive matching for existing formal transactions.
///
/// General-award evaluation is intentionally outside this service. Only
/// cloud-metadata identities enter this path, and each period+tier LKG index is
/// opened once for the small set of local candidate invoice numbers.
class ExistingInvoiceAwardCloudBatchMatcher {
  ExistingInvoiceAwardCloudBatchMatcher({
    required CloudAwardLatestSnapshotReader readLatest,
    this.lookup = const CloudAwardLocalIndexLookup(),
  }) : _readLatest = readLatest;

  final CloudAwardLatestSnapshotReader _readLatest;
  final CloudAwardLocalIndexLookup lookup;

  static const List<String> tierPriority = <String>[
    'cloud-1000000',
    'cloud-2000',
    'cloud-800',
    'cloud-500',
  ];

  static const Map<String, int> tierAmounts = <String, int>{
    'cloud-1000000': 1000000,
    'cloud-2000': 2000,
    'cloud-800': 800,
    'cloud-500': 500,
  };

  Future<List<ExistingInvoiceAwardCloudEvaluation>> evaluate({
    required Iterable<ExistingInvoiceAwardCandidate> candidates,
    Iterable<CloudAwardCandidateScopedAuthority> candidateScopedAuthorities =
        const <CloudAwardCandidateScopedAuthority>[],
  }) async {
    final scopedAuthorities =
        candidateScopedAuthorities.toList(growable: false);
    final frozen = candidates.toList(growable: false);
    final evaluations =
        <ExistingInvoiceAwardCandidate, ExistingInvoiceAwardCloudEvaluation>{};
    final groups = <String, List<ExistingInvoiceAwardCandidate>>{};

    for (final candidate in frozen) {
      if (candidate.identitySource !=
          ExistingInvoiceAwardIdentitySource.cloudMetadata) {
        evaluations[candidate] = _simple(
          candidate,
          ExistingInvoiceAwardCloudEvaluationStatus.notApplicable,
        );
        continue;
      }
      if (candidate.cloudEligibility ==
          ExistingInvoiceAwardCloudEligibility.ineligible) {
        evaluations[candidate] = _simple(
          candidate,
          ExistingInvoiceAwardCloudEvaluationStatus.ineligible,
        );
        continue;
      }
      final periodId = _cloudPeriodId(candidate.awardPeriod);
      if (periodId == null) {
        evaluations[candidate] = _simple(
          candidate,
          ExistingInvoiceAwardCloudEvaluationStatus.invalidPeriod,
        );
        continue;
      }
      groups.putIfAbsent(periodId, () => <ExistingInvoiceAwardCandidate>[])
          .add(candidate);
    }

    for (final entry in groups.entries) {
      final periodId = entry.key;
      final periodCandidates = entry.value;
      final invoiceNumbers = <String>{
        for (final candidate in periodCandidates)
          candidate.invoiceNumber.replaceAll(RegExp(r'[\s-]'), '').toUpperCase(),
      };

      final missingTiers = <String>{};
      final matchesByTier = <String, Set<String>>{};
      final snapshots = <String, CloudAwardValidatedIndexSnapshot>{};

      for (final tier in tierPriority) {
        CloudAwardCandidateScopedAuthority? scopedAuthority;
        for (final candidateAuthority in scopedAuthorities) {
          if (candidateAuthority.periodId == periodId &&
              candidateAuthority.tierCode == tier &&
              candidateAuthority.covers(
                periodId: periodId,
                tierCode: tier,
                invoiceNumbers: invoiceNumbers,
              )) {
            scopedAuthority = candidateAuthority;
            break;
          }
        }
        if (scopedAuthority != null) {
          matchesByTier[tier] = scopedAuthority.matchedInvoiceNumbers;
          continue;
        }

        final snapshot = await _readLatest(
          periodId: periodId,
          tierCode: tier,
        );
        if (snapshot == null) {
          missingTiers.add(tier);
          continue;
        }
        snapshots[tier] = snapshot;
        matchesByTier[tier] = await lookup.findMatches(
          indexFile: snapshot.indexFile,
          invoiceNumbers: invoiceNumbers,
        );
      }

      for (final candidate in periodCandidates) {
        final number = candidate.invoiceNumber
            .replaceAll(RegExp(r'[\s-]'), '')
            .toUpperCase();
        final matchedTiers = <String>{
          for (final tier in tierPriority)
            if (matchesByTier[tier]?.contains(number) ?? false) tier,
        };
        final selectedTier = matchedTiers.isEmpty
            ? null
            : tierPriority.firstWhere(matchedTiers.contains);
        final selectedSnapshot =
            selectedTier == null ? null : snapshots[selectedTier];

        late final ExistingInvoiceAwardCloudEvaluationStatus status;
        if (missingTiers.isNotEmpty) {
          status = ExistingInvoiceAwardCloudEvaluationStatus.authorityIncomplete;
        } else if (selectedTier == null) {
          status = ExistingInvoiceAwardCloudEvaluationStatus.notMatched;
        } else if (matchedTiers.length > 1) {
          status =
              ExistingInvoiceAwardCloudEvaluationStatus.anomalyReviewRequired;
        } else if (candidate.cloudEligibility ==
            ExistingInvoiceAwardCloudEligibility.eligible) {
          status = ExistingInvoiceAwardCloudEvaluationStatus.matchedEligible;
        } else {
          status =
              ExistingInvoiceAwardCloudEvaluationStatus.matchedReviewRequired;
        }

        evaluations[candidate] = ExistingInvoiceAwardCloudEvaluation(
          candidate: candidate,
          status: status,
          missingTierCodes: Set<String>.unmodifiable(missingTiers),
          matchedTierCodes: Set<String>.unmodifiable(matchedTiers),
          selectedTierCode: selectedTier,
          grossAmount:
              selectedTier == null ? 0 : (tierAmounts[selectedTier] ?? 0),
          indexSha256: selectedSnapshot?.manifest.indexSha256,
          pdfSha256: selectedSnapshot?.manifest.pdfSha256,
        );
      }
    }

    return List<ExistingInvoiceAwardCloudEvaluation>.unmodifiable(
      frozen.map(
        (candidate) =>
            evaluations[candidate] ??
            _simple(
              candidate,
              ExistingInvoiceAwardCloudEvaluationStatus.notApplicable,
            ),
      ),
    );
  }

  static ExistingInvoiceAwardCloudEvaluation _simple(
    ExistingInvoiceAwardCandidate candidate,
    ExistingInvoiceAwardCloudEvaluationStatus status,
  ) =>
      ExistingInvoiceAwardCloudEvaluation(
        candidate: candidate,
        status: status,
        missingTierCodes: const <String>{},
        matchedTierCodes: const <String>{},
      );

  static String? _cloudPeriodId(String awardPeriod) {
    final match = RegExp(r'^(\d{3})/(\d{2})$').firstMatch(awardPeriod);
    if (match == null) return null;
    final rocYear = int.tryParse(match.group(1)!);
    final endMonth = int.tryParse(match.group(2)!);
    if (rocYear == null ||
        endMonth == null ||
        endMonth < 2 ||
        endMonth > 12 ||
        endMonth.isOdd) {
      return null;
    }
    final startMonth = endMonth - 1;
    return '${rocYear.toString().padLeft(3, '0')}-'
        '${startMonth.toString().padLeft(2, '0')}-'
        '${endMonth.toString().padLeft(2, '0')}';
  }
}
