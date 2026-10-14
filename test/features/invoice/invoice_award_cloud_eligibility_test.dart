import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_eligibility.dart';

void main() {
  const resolver = InvoiceAwardCloudEligibilityResolver();
  final beforeDraw = DateTime.utc(2026, 7, 20);
  final afterDraw = DateTime.utc(2026, 7, 26);

  InvoiceAwardCloudEligibilityEvidence evidence(
    InvoiceAwardCloudEligibilityEvidenceKind kind, {
    DateTime? at,
    String sourceId = 'local-invoice-provenance',
  }) => InvoiceAwardCloudEligibilityEvidence(
    kind: kind,
    observedAt: at ?? beforeDraw,
    sourceId: sourceId,
  );

  test('approved carrier evidence can authorize cloud-exclusive matching', () {
    final result = resolver.resolve([
      evidence(InvoiceAwardCloudEligibilityEvidenceKind.approvedCarrier),
    ]);

    expect(result.status, InvoiceAwardCloudEligibilityStatus.eligible);
    expect(result.permitsCloudExclusiveMatching, isTrue);
    expect(result.canCreateFormalTransaction, isFalse);
  });

  test('known pre-draw proof printing is ineligible even with carrier evidence', () {
    final result = resolver.resolve([
      evidence(InvoiceAwardCloudEligibilityEvidenceKind.approvedCarrier),
      evidence(
        InvoiceAwardCloudEligibilityEvidenceKind
            .electronicInvoiceProofPrintedBeforeDraw,
      ),
    ]);

    expect(result.status, InvoiceAwardCloudEligibilityStatus.ineligible);
    expect(result.permitsCloudExclusiveMatching, isFalse);
  });

  test('post-draw proof printing does not itself remove eligibility', () {
    final result = resolver.resolve([
      evidence(InvoiceAwardCloudEligibilityEvidenceKind.approvedCarrier),
      evidence(
        InvoiceAwardCloudEligibilityEvidenceKind
            .electronicInvoiceProofPrintedAfterDraw,
        at: afterDraw,
      ),
    ]);

    expect(result.status, InvoiceAwardCloudEligibilityStatus.eligible);
    expect(result.permitsCloudExclusiveMatching, isTrue);
  });

  test('paper or OCR appearance alone remains unknown and review-required', () {
    final result = resolver.resolve([
      evidence(InvoiceAwardCloudEligibilityEvidenceKind.paperOrOcrAppearance),
    ]);

    expect(
      result.status,
      InvoiceAwardCloudEligibilityStatus.unknownReviewRequired,
    );
    expect(result.requiresReview, isTrue);
    expect(result.permitsCloudExclusiveMatching, isFalse);
  });

  test('missing or unusable provenance fails closed to unknown', () {
    final empty = resolver.resolve(const []);
    final missingSource = resolver.resolve([
      evidence(
        InvoiceAwardCloudEligibilityEvidenceKind.approvedCarrier,
        sourceId: ' ',
      ),
    ]);

    expect(empty.status, InvoiceAwardCloudEligibilityStatus.unknownReviewRequired);
    expect(
      missingSource.status,
      InvoiceAwardCloudEligibilityStatus.unknownReviewRequired,
    );
    expect(missingSource.permitsCloudExclusiveMatching, isFalse);
  });
}
