import 'existing_invoice_award_candidate_repository.dart';
import 'invoice_award_local_match_input.dart';
import 'invoice_award_official_dataset.dart';

enum ExistingInvoiceAwardGeneralEvaluationStatus {
  winner,
  notMatched,
  outOfPeriod,
  invalid,
}

class ExistingInvoiceAwardGeneralEvaluation {
  const ExistingInvoiceAwardGeneralEvaluation({
    required this.candidate,
    required this.status,
    required this.matchKind,
  });

  final ExistingInvoiceAwardCandidate candidate;
  final ExistingInvoiceAwardGeneralEvaluationStatus status;
  final OfficialInvoiceAwardMatchKind matchKind;

  bool get isWinner =>
      status == ExistingInvoiceAwardGeneralEvaluationStatus.winner;

  String get tierLabel => switch (matchKind) {
        OfficialInvoiceAwardMatchKind.special => '特別獎',
        OfficialInvoiceAwardMatchKind.grand => '特獎',
        OfficialInvoiceAwardMatchKind.first => '頭獎',
        OfficialInvoiceAwardMatchKind.second => '二獎',
        OfficialInvoiceAwardMatchKind.third => '三獎',
        OfficialInvoiceAwardMatchKind.fourth => '四獎',
        OfficialInvoiceAwardMatchKind.fifth => '五獎',
        OfficialInvoiceAwardMatchKind.sixth => '六獎',
        OfficialInvoiceAwardMatchKind.additionalSixth => '增開六獎',
        OfficialInvoiceAwardMatchKind.cloudExclusive => '雲端專屬獎',
        OfficialInvoiceAwardMatchKind.notMatched => '未中獎',
        OfficialInvoiceAwardMatchKind.invalid => '無法判定',
      };

  int get grossAmount => switch (matchKind) {
        OfficialInvoiceAwardMatchKind.special => 10000000,
        OfficialInvoiceAwardMatchKind.grand => 2000000,
        OfficialInvoiceAwardMatchKind.first => 200000,
        OfficialInvoiceAwardMatchKind.second => 40000,
        OfficialInvoiceAwardMatchKind.third => 10000,
        OfficialInvoiceAwardMatchKind.fourth => 4000,
        OfficialInvoiceAwardMatchKind.fifth => 1000,
        OfficialInvoiceAwardMatchKind.sixth ||
        OfficialInvoiceAwardMatchKind.additionalSixth =>
          200,
        OfficialInvoiceAwardMatchKind.cloudExclusive ||
        OfficialInvoiceAwardMatchKind.notMatched ||
        OfficialInvoiceAwardMatchKind.invalid =>
          0,
      };
}

/// Local-only batch evaluation of governed invoice identities already attached
/// to formal transactions.
///
/// This service has no network or persistence authority. Cloud-origin
/// transactions still receive the same general-award evaluation here; their
/// additional cloud-exclusive opportunity is evaluated by the separate cloud
/// dataset path.
class ExistingInvoiceAwardGeneralBatchMatcher {
  const ExistingInvoiceAwardGeneralBatchMatcher({
    this.validator = const OfficialInvoiceAwardDatasetValidator(),
  });

  final OfficialInvoiceAwardDatasetValidator validator;

  List<ExistingInvoiceAwardGeneralEvaluation> evaluate({
    required OfficialInvoiceAwardDataset dataset,
    required Iterable<ExistingInvoiceAwardCandidate> candidates,
  }) {
    if (!validator.validate(dataset).isValid) {
      return const <ExistingInvoiceAwardGeneralEvaluation>[];
    }

    final matcher = OfficialInvoiceAwardMatcher(validator: validator);
    final evaluations = <ExistingInvoiceAwardGeneralEvaluation>[];

    for (final candidate in candidates) {
      final input = InvoiceAwardLocalMatchInput(
        invoiceNumber: candidate.invoiceNumber,
        invoiceDate: candidate.invoiceDate,
      );
      if (!input.isValid) {
        evaluations.add(
          ExistingInvoiceAwardGeneralEvaluation(
            candidate: candidate,
            status: ExistingInvoiceAwardGeneralEvaluationStatus.invalid,
            matchKind: OfficialInvoiceAwardMatchKind.invalid,
          ),
        );
        continue;
      }

      if (input.period.id != dataset.period.id) {
        evaluations.add(
          ExistingInvoiceAwardGeneralEvaluation(
            candidate: candidate,
            status: ExistingInvoiceAwardGeneralEvaluationStatus.outOfPeriod,
            matchKind: OfficialInvoiceAwardMatchKind.notMatched,
          ),
        );
        continue;
      }

      final match = matcher.match(
        dataset: dataset,
        candidate: OfficialInvoiceAwardCandidate(
          invoiceNumber: candidate.invoiceNumber,
          period: input.period,
          cloudExclusiveEligible: false,
        ),
      );
      final status = switch (match.kind) {
        OfficialInvoiceAwardMatchKind.invalid =>
          ExistingInvoiceAwardGeneralEvaluationStatus.invalid,
        OfficialInvoiceAwardMatchKind.notMatched =>
          ExistingInvoiceAwardGeneralEvaluationStatus.notMatched,
        _ => ExistingInvoiceAwardGeneralEvaluationStatus.winner,
      };
      evaluations.add(
        ExistingInvoiceAwardGeneralEvaluation(
          candidate: candidate,
          status: status,
          matchKind: match.kind,
        ),
      );
    }

    return List<ExistingInvoiceAwardGeneralEvaluation>.unmodifiable(evaluations);
  }
}
