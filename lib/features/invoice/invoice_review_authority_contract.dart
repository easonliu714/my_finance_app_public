enum InvoiceReviewAuthorityFieldKind {
  invoiceId,
  issueDate,
  issueTime,
  totalAmount,
  merchant,
  lineItems,
}

enum InvoiceReviewAuthoritySource {
  qrPayload,
  explicitUserCorrection,
  explicitMasterSelection,
  defaultProfile,
}

enum InvoiceReviewAuthorityState {
  authoritative,
  supplemental,
  conflict,
  missing,
}

class InvoiceReviewFieldAuthority {
  const InvoiceReviewFieldAuthority({
    required this.kind,
    required this.state,
    this.source,
  });

  final InvoiceReviewAuthorityFieldKind kind;
  final InvoiceReviewAuthorityState state;
  final InvoiceReviewAuthoritySource? source;

  bool get isFormalHandoffAuthority {
    if (state != InvoiceReviewAuthorityState.authoritative || source == null) {
      return false;
    }

    switch (kind) {
      case InvoiceReviewAuthorityFieldKind.merchant:
        return source == InvoiceReviewAuthoritySource.qrPayload ||
            source == InvoiceReviewAuthoritySource.explicitUserCorrection ||
            source == InvoiceReviewAuthoritySource.explicitMasterSelection;
      case InvoiceReviewAuthorityFieldKind.invoiceId:
      case InvoiceReviewAuthorityFieldKind.issueDate:
      case InvoiceReviewAuthorityFieldKind.issueTime:
      case InvoiceReviewAuthorityFieldKind.totalAmount:
      case InvoiceReviewAuthorityFieldKind.lineItems:
        return source == InvoiceReviewAuthoritySource.qrPayload ||
            source == InvoiceReviewAuthoritySource.explicitUserCorrection;
    }
  }
}

enum InvoiceReviewAuthorityReasonCode {
  ready,
  fieldMissing,
  fieldConflict,
  fieldNotAuthoritative,
  duplicateFieldAuthority,
}

class InvoiceReviewAuthorityDecision {
  const InvoiceReviewAuthorityDecision({
    required this.isReady,
    required this.reasonCode,
    this.blockingField,
  });

  final bool isReady;
  final InvoiceReviewAuthorityReasonCode reasonCode;
  final InvoiceReviewAuthorityFieldKind? blockingField;
}

class InvoiceReviewAuthorityContract {
  const InvoiceReviewAuthorityContract();

  InvoiceReviewAuthorityDecision validateRequiredFields({
    required Iterable<InvoiceReviewFieldAuthority> fields,
    required Set<InvoiceReviewAuthorityFieldKind> requiredFields,
  }) {
    final byKind =
        <InvoiceReviewAuthorityFieldKind, List<InvoiceReviewFieldAuthority>>{};
    for (final field in fields) {
      (byKind[field.kind] ??= <InvoiceReviewFieldAuthority>[]).add(field);
    }

    for (final kind in InvoiceReviewAuthorityFieldKind.values) {
      if (!requiredFields.contains(kind)) {
        continue;
      }

      final matches = byKind[kind] ?? const <InvoiceReviewFieldAuthority>[];
      if (matches.length > 1) {
        return InvoiceReviewAuthorityDecision(
          isReady: false,
          reasonCode: InvoiceReviewAuthorityReasonCode.duplicateFieldAuthority,
          blockingField: kind,
        );
      }

      if (matches.isEmpty ||
          matches.single.state == InvoiceReviewAuthorityState.missing) {
        return InvoiceReviewAuthorityDecision(
          isReady: false,
          reasonCode: InvoiceReviewAuthorityReasonCode.fieldMissing,
          blockingField: kind,
        );
      }

      if (matches.single.state == InvoiceReviewAuthorityState.conflict) {
        return InvoiceReviewAuthorityDecision(
          isReady: false,
          reasonCode: InvoiceReviewAuthorityReasonCode.fieldConflict,
          blockingField: kind,
        );
      }

      if (!matches.single.isFormalHandoffAuthority) {
        return InvoiceReviewAuthorityDecision(
          isReady: false,
          reasonCode: InvoiceReviewAuthorityReasonCode.fieldNotAuthoritative,
          blockingField: kind,
        );
      }
    }

    return const InvoiceReviewAuthorityDecision(
      isReady: true,
      reasonCode: InvoiceReviewAuthorityReasonCode.ready,
    );
  }
}
