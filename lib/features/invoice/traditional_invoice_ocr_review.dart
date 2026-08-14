enum TraditionalInvoiceOcrStatus {
  success,
  partial,
  failed,
  invalidInput,
}

enum TraditionalInvoiceOcrField {
  invoiceNumber,
  sellerTaxId,
  invoiceDate,
  sellerName,
  totalAmount,
  visibleLineItems,
}

enum TraditionalInvoiceOcrConfidence {
  high,
  medium,
  low,
  unknown,
}

class TraditionalInvoiceOcrLineItem {
  const TraditionalInvoiceOcrLineItem({
    required this.name,
    this.amount,
    this.confidence = TraditionalInvoiceOcrConfidence.unknown,
    this.warnings = const <String>[],
  });

  final String name;
  final double? amount;
  final TraditionalInvoiceOcrConfidence confidence;
  final List<String> warnings;

  bool get isBlank => name.trim().isEmpty && amount == null;

  TraditionalInvoiceOcrLineItem copyWith({
    String? name,
    double? amount,
    bool clearAmount = false,
    TraditionalInvoiceOcrConfidence? confidence,
    List<String>? warnings,
  }) {
    return TraditionalInvoiceOcrLineItem(
      name: name ?? this.name,
      amount: clearAmount ? null : (amount ?? this.amount),
      confidence: confidence ?? this.confidence,
      warnings: warnings ?? this.warnings,
    );
  }
}

class TraditionalInvoiceOcrRecognition {
  const TraditionalInvoiceOcrRecognition({
    this.invoiceNumber,
    this.sellerTaxId,
    this.sellerTaxIdSource = '',
    this.invoiceDate,
    this.sellerName,
    this.totalAmount,
    this.visibleLineItems = const <TraditionalInvoiceOcrLineItem>[],
    this.confidence = const <TraditionalInvoiceOcrField,
        TraditionalInvoiceOcrConfidence>{},
    this.fieldWarnings = const <TraditionalInvoiceOcrField, List<String>>{},
    this.rawText = '',
    this.rawLines = const <String>[],
  });

  final String? invoiceNumber;
  final String? sellerTaxId;
  final String sellerTaxIdSource;
  final DateTime? invoiceDate;
  final String? sellerName;
  final double? totalAmount;
  final List<TraditionalInvoiceOcrLineItem> visibleLineItems;
  final Map<TraditionalInvoiceOcrField, TraditionalInvoiceOcrConfidence>
      confidence;
  final Map<TraditionalInvoiceOcrField, List<String>> fieldWarnings;
  final String rawText;
  final List<String> rawLines;
}

abstract class LocalTraditionalInvoiceRecognizer {
  Future<TraditionalInvoiceOcrRecognition> recognizeLocalImage(
    String localReference,
  );
}

class TraditionalInvoiceOcrReviewCandidate {
  const TraditionalInvoiceOcrReviewCandidate({
    required this.sourceImageReference,
    required this.invoiceNumber,
    this.sellerTaxId = '',
    this.sellerTaxIdSource = '',
    required this.invoiceDate,
    required this.sellerName,
    required this.totalAmount,
    required this.visibleLineItems,
    required this.confidence,
    required this.fieldWarnings,
    this.rawText = '',
    this.rawLines = const <String>[],
  });

  final String sourceImageReference;
  final String invoiceNumber;
  final String sellerTaxId;
  final String sellerTaxIdSource;
  final DateTime? invoiceDate;
  final String sellerName;
  final double? totalAmount;
  final List<TraditionalInvoiceOcrLineItem> visibleLineItems;
  final Map<TraditionalInvoiceOcrField, TraditionalInvoiceOcrConfidence>
      confidence;
  final Map<TraditionalInvoiceOcrField, List<String>> fieldWarnings;
  final String rawText;
  final List<String> rawLines;

  bool get usedNetwork => false;
  bool get canCreateFormalRecord => false;
  bool get requiresUserReview => true;

  bool get hasAnyRecognizedValue =>
      invoiceNumber.isNotEmpty ||
      sellerTaxId.isNotEmpty ||
      invoiceDate != null ||
      sellerName.isNotEmpty ||
      totalAmount != null ||
      visibleLineItems.isNotEmpty;

  bool get hasAllCoreFields =>
      invoiceNumber.isNotEmpty &&
      sellerTaxId.isNotEmpty &&
      invoiceDate != null &&
      totalAmount != null;

  TraditionalInvoiceOcrReviewCandidate copyWith({
    String? invoiceNumber,
    String? sellerTaxId,
    String? sellerTaxIdSource,
    DateTime? invoiceDate,
    bool clearInvoiceDate = false,
    String? sellerName,
    double? totalAmount,
    bool clearTotalAmount = false,
    List<TraditionalInvoiceOcrLineItem>? visibleLineItems,
  }) {
    return TraditionalInvoiceOcrReviewCandidate(
      sourceImageReference: sourceImageReference,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      sellerTaxId: sellerTaxId ?? this.sellerTaxId,
      sellerTaxIdSource: sellerTaxIdSource ?? this.sellerTaxIdSource,
      invoiceDate:
          clearInvoiceDate ? null : (invoiceDate ?? this.invoiceDate),
      sellerName: sellerName ?? this.sellerName,
      totalAmount:
          clearTotalAmount ? null : (totalAmount ?? this.totalAmount),
      visibleLineItems: visibleLineItems ?? this.visibleLineItems,
      confidence: confidence,
      fieldWarnings: fieldWarnings,
      rawText: rawText,
      rawLines: rawLines,
    );
  }

  Map<String, Object?> toSafeSummary() {
    return <String, Object?>{
      'hasInvoiceNumber': invoiceNumber.isNotEmpty,
      'hasSellerTaxId': sellerTaxId.isNotEmpty,
      'sellerTaxIdSource': sellerTaxIdSource,
      'hasInvoiceDate': invoiceDate != null,
      'hasSellerName': sellerName.isNotEmpty,
      'hasTotalAmount': totalAmount != null,
      'visibleLineItemCount': visibleLineItems.length,
      'warningFieldCount': fieldWarnings.values
          .where((warnings) => warnings.isNotEmpty)
          .length,
      'usedNetwork': usedNetwork,
      'canCreateFormalRecord': canCreateFormalRecord,
    };
  }
}

class TraditionalInvoiceOcrResult {
  const TraditionalInvoiceOcrResult({
    required this.status,
    required this.message,
    this.candidate,
    this.rawRecognition,
  });

  final TraditionalInvoiceOcrStatus status;
  final String message;
  final TraditionalInvoiceOcrReviewCandidate? candidate;
  final TraditionalInvoiceOcrRecognition? rawRecognition;

  bool get usedNetwork => false;
  bool get canCreateFormalRecord => false;
  bool get hasReviewCandidate => candidate != null;
}

class TraditionalInvoiceOcrCoordinator {
  const TraditionalInvoiceOcrCoordinator({required this.recognizer});

  final LocalTraditionalInvoiceRecognizer recognizer;

  Future<TraditionalInvoiceOcrResult> recognize(
    String localReference,
  ) async {
    final reference = localReference.trim();
    if (reference.isEmpty) {
      return const TraditionalInvoiceOcrResult(
        status: TraditionalInvoiceOcrStatus.invalidInput,
        message: '沒有可供本機辨識的影像。',
      );
    }

    try {
      final recognition = await recognizer.recognizeLocalImage(reference);
      final warnings = _normalizeWarnings(recognition.fieldWarnings);
      final invoiceNumber = recognition.invoiceNumber?.trim() ?? '';
      final sellerTaxId = recognition.sellerTaxId?.trim() ?? '';
      final sellerName = recognition.sellerName?.trim() ?? '';
      final totalAmount = _validAmount(
        recognition.totalAmount,
        warnings,
        TraditionalInvoiceOcrField.totalAmount,
      );
      final lineItems = recognition.visibleLineItems
          .map((item) => _normalizeLineItem(item))
          .where((item) => !item.isBlank)
          .toList(growable: false);

      final candidate = TraditionalInvoiceOcrReviewCandidate(
        sourceImageReference: reference,
        invoiceNumber: invoiceNumber,
        sellerTaxId: sellerTaxId,
        sellerTaxIdSource: recognition.sellerTaxIdSource,
        invoiceDate: recognition.invoiceDate,
        sellerName: sellerName,
        totalAmount: totalAmount,
        visibleLineItems:
            List<TraditionalInvoiceOcrLineItem>.unmodifiable(lineItems),
        confidence: Map<TraditionalInvoiceOcrField,
            TraditionalInvoiceOcrConfidence>.unmodifiable(
          recognition.confidence,
        ),
        fieldWarnings:
            Map<TraditionalInvoiceOcrField, List<String>>.unmodifiable(
          warnings,
        ),
        rawText: recognition.rawText,
        rawLines: List<String>.unmodifiable(recognition.rawLines),
      );

      if (!candidate.hasAnyRecognizedValue) {
        return TraditionalInvoiceOcrResult(
          status: TraditionalInvoiceOcrStatus.failed,
          message: '本機 OCR 未辨識到可供覆核的發票欄位。',
          rawRecognition: recognition,
        );
      }

      return TraditionalInvoiceOcrResult(
        status: candidate.hasAllCoreFields
            ? TraditionalInvoiceOcrStatus.success
            : TraditionalInvoiceOcrStatus.partial,
        message: candidate.hasAllCoreFields
            ? '已建立傳統發票 OCR 覆核候選，請確認所有欄位。'
            : '僅辨識到部分欄位；無法確認的內容已保持空白。',
        candidate: candidate,
        rawRecognition: recognition,
      );
    } catch (_) {
      return const TraditionalInvoiceOcrResult(
        status: TraditionalInvoiceOcrStatus.failed,
        message: '本機 OCR 辨識失敗，影像仍保留在待審核狀態。',
      );
    }
  }

  static Map<TraditionalInvoiceOcrField, List<String>> _normalizeWarnings(
    Map<TraditionalInvoiceOcrField, List<String>> input,
  ) {
    return <TraditionalInvoiceOcrField, List<String>>{
      for (final entry in input.entries)
        entry.key: List<String>.unmodifiable(
          entry.value
              .map((warning) => warning.trim())
              .where((warning) => warning.isNotEmpty),
        ),
    };
  }

  static double? _validAmount(
    double? value,
    Map<TraditionalInvoiceOcrField, List<String>> warnings,
    TraditionalInvoiceOcrField field,
  ) {
    if (value == null) return null;
    if (value.isNaN || value.isInfinite || value < 0) {
      final existing = warnings[field] ?? const <String>[];
      warnings[field] = List<String>.unmodifiable(
        <String>[...existing, '辨識金額無效，已保持空白。'],
      );
      return null;
    }
    return value;
  }

  static TraditionalInvoiceOcrLineItem _normalizeLineItem(
    TraditionalInvoiceOcrLineItem item,
  ) {
    final normalizedAmount = item.amount == null ||
            item.amount!.isNaN ||
            item.amount!.isInfinite ||
            item.amount! < 0
        ? null
        : item.amount;
    final warnings = <String>[
      ...item.warnings.map((warning) => warning.trim()).where(
            (warning) => warning.isNotEmpty,
          ),
      if (item.amount != null && normalizedAmount == null)
        '品項金額無效，已保持空白。',
    ];
    return TraditionalInvoiceOcrLineItem(
      name: item.name.trim(),
      amount: normalizedAmount,
      confidence: item.confidence,
      warnings: List<String>.unmodifiable(warnings),
    );
  }
}
