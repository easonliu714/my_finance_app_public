import 'invoice_review_handoff_contract.dart';
import 'traditional_invoice_ocr_review.dart';

enum InvoiceReviewFieldKey {
  invoiceNumber,
  invoiceDate,
  sellerTaxId,
  sellerName,
  totalAmount,
  invoicePeriod,
  randomCode,
}

class InvoiceReviewFieldViewModel {
  const InvoiceReviewFieldViewModel({
    required this.key,
    required this.label,
    required this.value,
    required this.editable,
    required this.requiredForReview,
    this.confidenceLabel = '',
    this.warnings = const <String>[],
  });

  final InvoiceReviewFieldKey key;
  final String label;
  final String value;
  final bool editable;
  final bool requiredForReview;
  final String confidenceLabel;
  final List<String> warnings;

  bool get isBlank => value.trim().isEmpty;
  bool get needsAttention => warnings.isNotEmpty || isBlank;

  InvoiceReviewFieldViewModel copyWithValue(String nextValue) {
    return InvoiceReviewFieldViewModel(
      key: key,
      label: label,
      value: nextValue.trim(),
      editable: editable,
      requiredForReview: requiredForReview,
      confidenceLabel: confidenceLabel,
      warnings: warnings,
    );
  }
}

class InvoiceReviewLineItemViewModel {
  const InvoiceReviewLineItemViewModel({
    required this.name,
    required this.amountText,
    this.confidenceLabel = '',
    this.warnings = const <String>[],
  });

  final String name;
  final String amountText;
  final String confidenceLabel;
  final List<String> warnings;

  bool get isBlank => name.trim().isEmpty && amountText.trim().isEmpty;
}

class InvoiceReviewFormViewModel {
  const InvoiceReviewFormViewModel({
    required this.title,
    required this.routeReason,
    required this.disclaimer,
    required this.fields,
    required this.lineItems,
    required this.warnings,
    required this.availableOverrides,
    required this.canOpenReview,
    required this.requiresAcknowledgement,
    required this.disclaimerAcknowledged,
  });

  final String title;
  final String routeReason;
  final String disclaimer;
  final List<InvoiceReviewFieldViewModel> fields;
  final List<InvoiceReviewLineItemViewModel> lineItems;
  final List<String> warnings;
  final List<InvoiceReviewRouteOverride> availableOverrides;
  final bool canOpenReview;
  final bool requiresAcknowledgement;
  final bool disclaimerAcknowledged;

  bool get usedNetwork => false;
  bool get canCreateFormalRecord => false;
  bool get canSubmitForReview =>
      canOpenReview &&
      (!requiresAcknowledgement || disclaimerAcknowledged);

  InvoiceReviewFieldViewModel? fieldFor(InvoiceReviewFieldKey key) {
    for (final field in fields) {
      if (field.key == key) return field;
    }
    return null;
  }

  InvoiceReviewFormViewModel updateField(
    InvoiceReviewFieldKey key,
    String value,
  ) {
    return InvoiceReviewFormViewModel(
      title: title,
      routeReason: routeReason,
      disclaimer: disclaimer,
      fields: List<InvoiceReviewFieldViewModel>.unmodifiable(
        fields.map(
          (field) => field.key == key ? field.copyWithValue(value) : field,
        ),
      ),
      lineItems: lineItems,
      warnings: warnings,
      availableOverrides: availableOverrides,
      canOpenReview: canOpenReview,
      requiresAcknowledgement: requiresAcknowledgement,
      disclaimerAcknowledged: disclaimerAcknowledged,
    );
  }

  InvoiceReviewFormViewModel acknowledgeDisclaimer(bool acknowledged) {
    return InvoiceReviewFormViewModel(
      title: title,
      routeReason: routeReason,
      disclaimer: disclaimer,
      fields: fields,
      lineItems: lineItems,
      warnings: warnings,
      availableOverrides: availableOverrides,
      canOpenReview: canOpenReview,
      requiresAcknowledgement: requiresAcknowledgement,
      disclaimerAcknowledged: acknowledged,
    );
  }

  Map<String, Object?> toSafeSummary() {
    return <String, Object?>{
      'hasRouteReason': routeReason.trim().isNotEmpty,
      'hasDisclaimer': disclaimer == invoiceRecognitionDisclaimer,
      'fieldCount': fields.length,
      'blankFieldCount': fields.where((field) => field.isBlank).length,
      'lineItemCount': lineItems.length,
      'warningCount': warnings.length,
      'canOpenReview': canOpenReview,
      'canSubmitForReview': canSubmitForReview,
      'canCreateFormalRecord': canCreateFormalRecord,
      'usedNetwork': usedNetwork,
    };
  }
}

class InvoiceReviewFormPresenter {
  const InvoiceReviewFormPresenter();

  InvoiceReviewFormViewModel fromHandoff(
    InvoiceReviewHandoffState state,
  ) {
    switch (state.action) {
      case InvoiceReviewHandoffAction.reviewQrCandidate:
        return _fromQr(state);
      case InvoiceReviewHandoffAction.reviewTraditionalOcrCandidate:
        return _fromOcr(state);
      case InvoiceReviewHandoffAction.designateQrManually:
      case InvoiceReviewHandoffAction.retryCapture:
      case InvoiceReviewHandoffAction.enterManually:
        return _blocked(state);
    }
  }

  InvoiceReviewFormViewModel _fromQr(InvoiceReviewHandoffState state) {
    final pairs = state.automaticResult?.qrResult?.routingResult?.pairs;
    final pair = pairs == null || pairs.isEmpty ? null : pairs.first;
    final parsed = pair?.left.leftParseResult;
    final fields = <InvoiceReviewFieldViewModel>[
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoiceNumber,
        label: '\u767c\u7968\u865f\u78bc',
        value: parsed?.invoiceNumber?.trim() ?? '',
        editable: true,
        requiredForReview: true,
        confidenceLabel: parsed?.invoiceNumber == null
            ? '\u672a\u8fa8\u8b58'
            : 'QR \u89e3\u6790',
        warnings: parsed?.warnings ?? const <String>[],
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoiceDate,
        label: '\u767c\u7968\u65e5\u671f',
        value: _formatDate(parsed?.invoiceDate),
        editable: true,
        requiredForReview: true,
        confidenceLabel: parsed?.invoiceDate == null
            ? '\u672a\u8fa8\u8b58'
            : 'QR \u89e3\u6790',
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.sellerName,
        label: '\u5546\u5bb6',
        value: _sellerLabel(parsed?.sellerIdentifier),
        editable: true,
        requiredForReview: false,
        confidenceLabel: parsed?.sellerIdentifier == null
            ? '\u672a\u8fa8\u8b58'
            : 'QR \u89e3\u6790',
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.totalAmount,
        label: '\u7e3d\u91d1\u984d',
        value: parsed?.totalAmount?.toString() ?? '',
        editable: true,
        requiredForReview: true,
        confidenceLabel: parsed?.totalAmount == null
            ? '\u672a\u8fa8\u8b58'
            : 'QR \u89e3\u6790',
      ),
    ];

    return InvoiceReviewFormViewModel(
      title: state.title,
      routeReason: state.routeReason,
      disclaimer: state.disclaimer,
      fields: List<InvoiceReviewFieldViewModel>.unmodifiable(fields),
      lineItems: const <InvoiceReviewLineItemViewModel>[],
      warnings: List<String>.unmodifiable(
        <String>[
          ...state.warnings,
          ...?pair?.warnings,
        ],
      ),
      availableOverrides: state.availableOverrides,
      canOpenReview: pair?.canCreateReviewCandidate == true,
      requiresAcknowledgement: true,
      disclaimerAcknowledged: false,
    );
  }

  InvoiceReviewFormViewModel _fromOcr(InvoiceReviewHandoffState state) {
    final candidate = state.automaticResult?.ocrResult?.candidate;
    final fields = <InvoiceReviewFieldViewModel>[
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoiceNumber,
        label: '\u767c\u7968\u865f\u78bc',
        value: candidate?.invoiceNumber.trim() ?? '',
        editable: true,
        requiredForReview: true,
        confidenceLabel: _confidenceLabel(
          candidate?.confidence[TraditionalInvoiceOcrField.invoiceNumber],
        ),
        warnings: candidate?.fieldWarnings[
              TraditionalInvoiceOcrField.invoiceNumber
            ] ??
            const <String>[],
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoiceDate,
        label: '\u767c\u7968\u65e5\u671f',
        value: _formatDate(candidate?.invoiceDate),
        editable: true,
        requiredForReview: true,
        confidenceLabel: _confidenceLabel(
          candidate?.confidence[TraditionalInvoiceOcrField.invoiceDate],
        ),
        warnings:
            candidate?.fieldWarnings[TraditionalInvoiceOcrField.invoiceDate] ??
                const <String>[],
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.sellerName,
        label: '\u5546\u5bb6',
        value: candidate?.sellerName.trim() ?? '',
        editable: true,
        requiredForReview: false,
        confidenceLabel: _confidenceLabel(
          candidate?.confidence[TraditionalInvoiceOcrField.sellerName],
        ),
        warnings:
            candidate?.fieldWarnings[TraditionalInvoiceOcrField.sellerName] ??
                const <String>[],
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.totalAmount,
        label: '\u7e3d\u91d1\u984d',
        value: candidate?.totalAmount?.toString() ?? '',
        editable: true,
        requiredForReview: true,
        confidenceLabel: _confidenceLabel(
          candidate?.confidence[TraditionalInvoiceOcrField.totalAmount],
        ),
        warnings:
            candidate?.fieldWarnings[TraditionalInvoiceOcrField.totalAmount] ??
                const <String>[],
      ),
    ];

    final lineItems = candidate?.visibleLineItems
            .map(
              (item) => InvoiceReviewLineItemViewModel(
                name: item.name.trim(),
                amountText: item.amount?.toString() ?? '',
                confidenceLabel: _confidenceLabel(item.confidence),
                warnings: item.warnings,
              ),
            )
            .where((item) => !item.isBlank)
            .toList(growable: false) ??
        const <InvoiceReviewLineItemViewModel>[];

    return InvoiceReviewFormViewModel(
      title: state.title,
      routeReason: state.routeReason,
      disclaimer: state.disclaimer,
      fields: List<InvoiceReviewFieldViewModel>.unmodifiable(fields),
      lineItems: List<InvoiceReviewLineItemViewModel>.unmodifiable(lineItems),
      warnings: state.warnings,
      availableOverrides: state.availableOverrides,
      canOpenReview: candidate != null,
      requiresAcknowledgement: true,
      disclaimerAcknowledged: false,
    );
  }

  InvoiceReviewFormViewModel _blocked(InvoiceReviewHandoffState state) {
    return InvoiceReviewFormViewModel(
      title: state.title,
      routeReason: state.routeReason,
      disclaimer: state.disclaimer,
      fields: const <InvoiceReviewFieldViewModel>[],
      lineItems: const <InvoiceReviewLineItemViewModel>[],
      warnings: state.warnings,
      availableOverrides: state.availableOverrides,
      canOpenReview: false,
      requiresAcknowledgement: false,
      disclaimerAcknowledged: false,
    );
  }

  static String _formatDate(DateTime? value) {
    if (value == null) return '';
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  static String _sellerLabel(String? sellerIdentifier) {
    final identifier = sellerIdentifier?.trim() ?? '';
    return identifier.isEmpty
        ? ''
        : '\u8ce3\u65b9\u7d71\u7de8 $identifier';
  }

  static String _confidenceLabel(
    TraditionalInvoiceOcrConfidence? confidence,
  ) {
    if (confidence == null) return '\u672a\u63d0\u4f9b';
    switch (confidence) {
      case TraditionalInvoiceOcrConfidence.high:
        return '\u9ad8';
      case TraditionalInvoiceOcrConfidence.medium:
        return '\u4e2d';
      case TraditionalInvoiceOcrConfidence.low:
        return '\u4f4e';
      case TraditionalInvoiceOcrConfidence.unknown:
        return '\u672a\u63d0\u4f9b';
    }
  }
}
