enum InvoiceAwardCloudEligibilityStatus {
  eligible,
  ineligible,
  unknownReviewRequired,
}

enum InvoiceAwardCloudEligibilityEvidenceKind {
  approvedCarrier,
  donation,
  electronicInvoiceProofPrintedBeforeDraw,
  electronicInvoiceProofPrintedAfterDraw,
  paperOrOcrAppearance,
  unknown,
}

class InvoiceAwardCloudEligibilityEvidence {
  const InvoiceAwardCloudEligibilityEvidence({
    required this.kind,
    required this.observedAt,
    required this.sourceId,
    this.detail,
  });

  final InvoiceAwardCloudEligibilityEvidenceKind kind;
  final DateTime observedAt;
  final String sourceId;
  final String? detail;

  bool get hasUsableProvenance =>
      sourceId.trim().isNotEmpty && observedAt.isUtc;
}

class InvoiceAwardCloudEligibility {
  const InvoiceAwardCloudEligibility({
    required this.status,
    required this.evidence,
  });

  final InvoiceAwardCloudEligibilityStatus status;
  final List<InvoiceAwardCloudEligibilityEvidence> evidence;

  bool get permitsCloudExclusiveMatching =>
      status == InvoiceAwardCloudEligibilityStatus.eligible &&
      evidence.isNotEmpty &&
      evidence.every((item) => item.hasUsableProvenance) &&
      evidence.any(
        (item) =>
            item.kind == InvoiceAwardCloudEligibilityEvidenceKind.approvedCarrier ||
            item.kind == InvoiceAwardCloudEligibilityEvidenceKind.donation,
      ) &&
      !evidence.any(
        (item) =>
            item.kind ==
            InvoiceAwardCloudEligibilityEvidenceKind
                .electronicInvoiceProofPrintedBeforeDraw,
      );

  bool get requiresReview =>
      status == InvoiceAwardCloudEligibilityStatus.unknownReviewRequired;

  bool get canCreateFormalTransaction => false;
}

class InvoiceAwardCloudEligibilityResolver {
  const InvoiceAwardCloudEligibilityResolver();

  InvoiceAwardCloudEligibility resolve(
    List<InvoiceAwardCloudEligibilityEvidence> evidence,
  ) {
    final frozen = List<InvoiceAwardCloudEligibilityEvidence>.unmodifiable(
      evidence,
    );
    if (frozen.isEmpty || frozen.any((item) => !item.hasUsableProvenance)) {
      return InvoiceAwardCloudEligibility(
        status: InvoiceAwardCloudEligibilityStatus.unknownReviewRequired,
        evidence: frozen,
      );
    }

    if (frozen.any(
      (item) =>
          item.kind ==
          InvoiceAwardCloudEligibilityEvidenceKind
              .electronicInvoiceProofPrintedBeforeDraw,
    )) {
      return InvoiceAwardCloudEligibility(
        status: InvoiceAwardCloudEligibilityStatus.ineligible,
        evidence: frozen,
      );
    }

    final hasPositiveAuthority = frozen.any(
      (item) =>
          item.kind == InvoiceAwardCloudEligibilityEvidenceKind.approvedCarrier ||
          item.kind == InvoiceAwardCloudEligibilityEvidenceKind.donation,
    );
    if (hasPositiveAuthority) {
      return InvoiceAwardCloudEligibility(
        status: InvoiceAwardCloudEligibilityStatus.eligible,
        evidence: frozen,
      );
    }

    return InvoiceAwardCloudEligibility(
      status: InvoiceAwardCloudEligibilityStatus.unknownReviewRequired,
      evidence: frozen,
    );
  }
}
