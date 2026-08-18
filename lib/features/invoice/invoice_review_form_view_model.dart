import 'invoice_local_completeness_policy.dart';
import 'invoice_review_handoff_contract.dart';
import 'traditional_invoice_ocr_review.dart';

enum InvoiceReviewFieldKey {
  invoiceNumber,
  invoiceDate,
  invoiceTime,
  sellerTaxId,
  sellerName,
  totalAmount,
  invoicePeriod,
  randomCode,
}

String extractCanonicalInvoicePeriod(String rawText) {
  final normalized = rawText
      .replaceAll('－', '-')
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('〜', '~');
  final matches = RegExp(
    r'(?:中華民國)?\s*(\d{2,3})\s*年\s*(\d{1,2})\s*[-~～至]\s*(\d{1,2})\s*月(?:份)?',
  ).allMatches(normalized);
  final canonical = <String>{};
  for (final match in matches) {
    final year = int.tryParse(match.group(1)!);
    final startMonth = int.tryParse(match.group(2)!);
    final endMonth = int.tryParse(match.group(3)!);
    if (year == null || year < 80 || year > 200) continue;
    if (startMonth == null || endMonth == null) continue;
    if (startMonth < 1 || endMonth > 12 || startMonth > endMonth) continue;
    canonical.add('$year年$startMonth-$endMonth月份');
  }
  return canonical.length == 1 ? canonical.single : '';
}

String normalizeInvoicePeriodForComparison(String value) {
  final canonical = extractCanonicalInvoicePeriod(value);
  if (canonical.isEmpty) return '';
  final match = RegExp(r'^(\d{2,3})年(\d{1,2})-(\d{1,2})月份$')
      .firstMatch(canonical);
  if (match == null) return '';
  final year = match.group(1)!;
  final startMonth = match.group(2)!.padLeft(2, '0');
  final endMonth = match.group(3)!.padLeft(2, '0');
  return '$year-$startMonth-$endMonth';
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
      canOpenReview && (!requiresAcknowledgement || disclaimerAcknowledged);

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

  InvoiceReviewFormViewModel fromHandoff(InvoiceReviewHandoffState state) {
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
    final supplemental = state.automaticResult?.ocrResult?.candidate;
    final supplementalRawText =
        supplemental?.rawText ??
        state.automaticResult?.ocrResult?.rawRecognition?.rawText ??
        '';
    final invoiceTime = extractStrictInvoiceTime(supplementalRawText);
    final invoicePeriod = extractCanonicalInvoicePeriod(supplementalRawText);
    final fields = <InvoiceReviewFieldViewModel>[
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoiceNumber,
        label: '發票號碼',
        value: parsed?.invoiceNumber?.trim() ?? '',
        editable: true,
        requiredForReview: true,
        confidenceLabel: parsed?.invoiceNumber == null ? '未辨識' : 'QR 解析',
        warnings: parsed?.warnings ?? const <String>[],
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoicePeriod,
        label: '發票期別',
        value: invoicePeriod,
        editable: true,
        requiredForReview: false,
        confidenceLabel: invoicePeriod.isEmpty ? '未辨識' : '本機 OCR 補充',
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoiceDate,
        label: '發票日期',
        value: _formatDate(parsed?.invoiceDate),
        editable: true,
        requiredForReview: true,
        confidenceLabel: parsed?.invoiceDate == null ? '未辨識' : 'QR 解析',
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoiceTime,
        label: '交易時間',
        value: invoiceTime,
        editable: true,
        requiredForReview: true,
        confidenceLabel: invoiceTime.isEmpty ? '未辨識' : '本機 OCR 補充',
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.sellerTaxId,
        label: '賣方統編',
        value: parsed?.sellerIdentifier?.trim() ?? '',
        editable: true,
        requiredForReview: true,
        confidenceLabel: parsed?.sellerIdentifier == null ? '未辨識' : 'QR 解析',
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.sellerName,
        label: '商家名稱',
        value: supplemental?.sellerName.trim() ?? '',
        editable: true,
        requiredForReview: true,
        confidenceLabel: supplemental?.sellerName.trim().isNotEmpty == true
            ? '本機 OCR 補充'
            : '未辨識',
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.totalAmount,
        label: '總金額',
        value: parsed?.totalAmount?.toString() ?? '',
        editable: true,
        requiredForReview: true,
        confidenceLabel: parsed?.totalAmount == null ? '未辨識' : 'QR 解析',
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.randomCode,
        label: '隨機碼',
        value: parsed?.randomCode?.trim() ?? '',
        editable: true,
        requiredForReview: false,
        confidenceLabel: parsed?.randomCode == null ? '未辨識' : 'QR 解析',
      ),
    ];

    return InvoiceReviewFormViewModel(
      title: state.title,
      routeReason: state.routeReason,
      disclaimer: state.disclaimer,
      fields: List<InvoiceReviewFieldViewModel>.unmodifiable(fields),
      lineItems: const <InvoiceReviewLineItemViewModel>[],
      warnings: List<String>.unmodifiable(<String>[
        ...state.warnings,
        ...?pair?.warnings,
      ]),
      availableOverrides: state.availableOverrides,
      canOpenReview: pair?.canCreateReviewCandidate == true,
      requiresAcknowledgement: true,
      disclaimerAcknowledged: false,
    );
  }

  InvoiceReviewFormViewModel _fromOcr(InvoiceReviewHandoffState state) {
    final candidate = state.automaticResult?.ocrResult?.candidate;
    final rawText = candidate?.rawText ?? '';
    final invoiceTime = extractStrictInvoiceTime(rawText);
    final invoicePeriod = extractCanonicalInvoicePeriod(rawText);
    final fields = <InvoiceReviewFieldViewModel>[
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoiceNumber,
        label: '發票號碼',
        value: candidate?.invoiceNumber.trim() ?? '',
        editable: true,
        requiredForReview: true,
        confidenceLabel: _confidenceLabel(
          candidate?.confidence[TraditionalInvoiceOcrField.invoiceNumber],
        ),
        warnings:
            candidate?.fieldWarnings[TraditionalInvoiceOcrField.invoiceNumber] ??
            const <String>[],
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoicePeriod,
        label: '發票期別',
        value: invoicePeriod,
        editable: true,
        requiredForReview: false,
        confidenceLabel: invoicePeriod.isEmpty ? '未辨識' : '本機 OCR',
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoiceDate,
        label: '發票日期',
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
        key: InvoiceReviewFieldKey.invoiceTime,
        label: '交易時間',
        value: invoiceTime,
        editable: true,
        requiredForReview: false,
        confidenceLabel: invoiceTime.isEmpty ? '未辨識' : '本機 OCR',
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.sellerTaxId,
        label: '賣方統編',
        value: candidate?.sellerTaxId.trim() ?? '',
        editable: true,
        requiredForReview: true,
        confidenceLabel: _confidenceLabel(
          candidate?.confidence[TraditionalInvoiceOcrField.sellerTaxId],
        ),
        warnings:
            candidate?.fieldWarnings[TraditionalInvoiceOcrField.sellerTaxId] ??
            const <String>[],
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.sellerName,
        label: '商家名稱',
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
        label: '總金額',
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
      const InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.randomCode,
        label: '隨機碼',
        value: '',
        editable: true,
        requiredForReview: false,
        confidenceLabel: '未辨識',
      ),
    ];

    final lineItems =
        candidate?.visibleLineItems
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

  static String _confidenceLabel(TraditionalInvoiceOcrConfidence? confidence) {
    if (confidence == null) return '未提供';
    switch (confidence) {
      case TraditionalInvoiceOcrConfidence.high:
        return '高';
      case TraditionalInvoiceOcrConfidence.medium:
        return '中';
      case TraditionalInvoiceOcrConfidence.low:
        return '低';
      case TraditionalInvoiceOcrConfidence.unknown:
        return '未提供';
    }
  }
}
