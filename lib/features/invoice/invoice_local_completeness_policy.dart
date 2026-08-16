import 'invoice_automatic_recognition_coordinator.dart';

enum InvoiceLocalCompletenessField {
  invoiceNumber,
  invoiceDate,
  invoiceTime,
  sellerTaxId,
  sellerName,
  totalAmount,
}

class InvoiceLocalCompletenessDecision {
  const InvoiceLocalCompletenessDecision({
    required this.requiresGeminiReview,
    required this.missingFields,
    required this.reason,
    required this.isElectronic,
  });
  final bool requiresGeminiReview;
  final List<InvoiceLocalCompletenessField> missingFields;
  final String reason;
  final bool isElectronic;
}

String extractStrictInvoiceTime(String rawText) {
  final normalized = rawText.replaceAll('：', ':');
  final matches = RegExp(
    r'(?<!\d)([01]\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?(?!\d)',
  ).allMatches(normalized).map((match) => match.group(0)!).toSet();
  if (matches.length != 1) return '';
  return matches.single;
}

class InvoiceLocalCompletenessPolicy {
  const InvoiceLocalCompletenessPolicy();
  InvoiceLocalCompletenessDecision evaluate(
    InvoiceAutomaticRecognitionResult result,
  ) {
    if (result.status == InvoiceAutomaticRecognitionStatus.qrReviewCandidate)
      return _electronic(result);
    if (result.status == InvoiceAutomaticRecognitionStatus.ocrReviewCandidate)
      return _traditional(result);
    return InvoiceLocalCompletenessDecision(
      requiresGeminiReview:
          result.status != InvoiceAutomaticRecognitionStatus.invalidInput,
      missingFields: const <InvoiceLocalCompletenessField>[],
      reason: result.status == InvoiceAutomaticRecognitionStatus.invalidInput
          ? '本機輸入無效，不應送出影像。'
          : '本機尚未建立完整覆核候選，需要 Gemini 或人工覆核。',
      isElectronic: false,
    );
  }

  InvoiceLocalCompletenessDecision _electronic(
    InvoiceAutomaticRecognitionResult result,
  ) {
    final pairs = result.qrResult?.routingResult?.pairs;
    final parsed = pairs == null || pairs.isEmpty
        ? null
        : pairs.first.left.leftParseResult;
    final supplemental = result.ocrResult?.candidate;
    final rawText =
        supplemental?.rawText ??
        result.ocrResult?.rawRecognition?.rawText ??
        '';
    final missing = <InvoiceLocalCompletenessField>[
      if ((parsed?.invoiceNumber ?? '').trim().isEmpty)
        InvoiceLocalCompletenessField.invoiceNumber,
      if (parsed?.invoiceDate == null)
        InvoiceLocalCompletenessField.invoiceDate,
      if (extractStrictInvoiceTime(rawText).isEmpty)
        InvoiceLocalCompletenessField.invoiceTime,
      if ((parsed?.sellerIdentifier ?? '').trim().isEmpty)
        InvoiceLocalCompletenessField.sellerTaxId,
      if ((supplemental?.sellerName ?? '').trim().isEmpty)
        InvoiceLocalCompletenessField.sellerName,
      if (parsed?.totalAmount == null)
        InvoiceLocalCompletenessField.totalAmount,
    ];
    return InvoiceLocalCompletenessDecision(
      requiresGeminiReview: missing.isNotEmpty,
      missingFields: List.unmodifiable(missing),
      reason: missing.isEmpty
          ? '電子發票 Local 關鍵欄位完整，不需強制 Gemini。'
          : '電子發票 Local 缺少${_labels(missing).join('、')}，需要 Gemini 覆核後由使用者確認。',
      isElectronic: true,
    );
  }

  InvoiceLocalCompletenessDecision _traditional(
    InvoiceAutomaticRecognitionResult result,
  ) {
    final candidate = result.ocrResult?.candidate;
    final missing = <InvoiceLocalCompletenessField>[
      if ((candidate?.invoiceNumber ?? '').trim().isEmpty)
        InvoiceLocalCompletenessField.invoiceNumber,
      if (candidate?.invoiceDate == null)
        InvoiceLocalCompletenessField.invoiceDate,
      if ((candidate?.sellerTaxId ?? '').trim().isEmpty)
        InvoiceLocalCompletenessField.sellerTaxId,
      if ((candidate?.sellerName ?? '').trim().isEmpty)
        InvoiceLocalCompletenessField.sellerName,
      if (candidate?.totalAmount == null)
        InvoiceLocalCompletenessField.totalAmount,
    ];
    return InvoiceLocalCompletenessDecision(
      requiresGeminiReview: missing.isNotEmpty,
      missingFields: List.unmodifiable(missing),
      reason: missing.isEmpty
          ? '傳統發票 Local 關鍵欄位完整。'
          : '傳統發票 Local 缺少${_labels(missing).join('、')}，需要 Gemini 或人工覆核。',
      isElectronic: false,
    );
  }

  static List<String> _labels(List<InvoiceLocalCompletenessField> fields) =>
      fields
          .map(
            (field) => switch (field) {
              InvoiceLocalCompletenessField.invoiceNumber => '發票號碼',
              InvoiceLocalCompletenessField.invoiceDate => '交易日期',
              InvoiceLocalCompletenessField.invoiceTime => '交易時間',
              InvoiceLocalCompletenessField.sellerTaxId => '賣方統編',
              InvoiceLocalCompletenessField.sellerName => '商家名稱',
              InvoiceLocalCompletenessField.totalAmount => '總金額',
            },
          )
          .toList(growable: false);
}
