import 'invoice_field_first_evidence.dart';
import 'invoice_review_form_view_model.dart';
import 'invoice_review_handoff_contract.dart';
import 'traditional_invoice_ocr_review.dart';

class FieldFirstInvoiceReviewFormPresenter extends InvoiceReviewFormPresenter {
  const FieldFirstInvoiceReviewFormPresenter();

  @override
  InvoiceReviewFormViewModel fromHandoff(InvoiceReviewHandoffState state) {
    final base = super.fromHandoff(state);
    if (!base.canOpenReview) return base;

    final automatic = state.automaticResult;
    final qrPairs = automatic?.qrResult?.routingResult?.pairs;
    final qrParsed = qrPairs == null || qrPairs.isEmpty
        ? null
        : qrPairs.first.left.leftParseResult;
    final ocr = automatic?.ocrResult?.candidate;
    final raw = automatic?.ocrResult?.rawRecognition;
    final fieldEvidence = parseInvoiceFieldFirstEvidence(
      ocr?.rawLines ?? raw?.rawLines ?? const <String>[],
    );

    final qrRandomCode = qrParsed?.randomCode?.trim() ?? '';
    final randomCode =
        qrRandomCode.isNotEmpty ? qrRandomCode : fieldEvidence.randomCode;
    final randomCodeConfidence = qrRandomCode.isNotEmpty
        ? 'QR 解析'
        : fieldEvidence.randomCode.isNotEmpty
            ? 'OCR 標籤'
            : '未辨識';

    final qrSellerTaxId = qrParsed?.sellerIdentifier?.trim() ?? '';
    final sellerTaxId = qrSellerTaxId.isNotEmpty
        ? qrSellerTaxId
        : ocr?.sellerTaxId.trim() ?? '';
    final sellerTaxConfidence = qrSellerTaxId.isNotEmpty
        ? 'QR 解析'
        : ocr?.sellerTaxId.isNotEmpty == true
            ? _ocrConfidenceLabel(
                ocr?.confidence[TraditionalInvoiceOcrField.sellerTaxId],
                source: ocr?.sellerTaxIdSource ?? '',
              )
            : '未辨識';
    final sellerTaxWarnings = qrSellerTaxId.isNotEmpty
        ? const <String>[]
        : ocr?.fieldWarnings[TraditionalInvoiceOcrField.sellerTaxId] ??
            const <String>[];

    final baseMerchant =
        base.fieldFor(InvoiceReviewFieldKey.sellerName)?.value.trim() ?? '';
    final merchantName = ocr?.sellerName.trim().isNotEmpty == true
        ? ocr!.sellerName.trim()
        : baseMerchant.startsWith('賣方統編')
            ? ''
            : baseMerchant;

    final fields = <InvoiceReviewFieldViewModel>[
      if (base.fieldFor(InvoiceReviewFieldKey.invoiceNumber) case final field?)
        field,
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoicePeriod,
        label: '發票期別',
        value: fieldEvidence.invoicePeriod,
        editable: true,
        requiredForReview: false,
        confidenceLabel:
            fieldEvidence.invoicePeriod.isEmpty ? '未辨識' : 'OCR 版面',
      ),
      if (base.fieldFor(InvoiceReviewFieldKey.invoiceDate) case final field?)
        field,
      // P4.18.3: Field-First decorates the base form but must not drop the
      // strict Local OCR transaction time already produced by the base presenter.
      if (base.fieldFor(InvoiceReviewFieldKey.invoiceTime) case final field?)
        field,
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.sellerTaxId,
        label: '賣方統編',
        value: sellerTaxId,
        editable: true,
        requiredForReview: true,
        confidenceLabel: sellerTaxConfidence,
        warnings: sellerTaxWarnings,
      ),
      if (base.fieldFor(InvoiceReviewFieldKey.totalAmount) case final field?)
        field,
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.randomCode,
        label: '隨機碼',
        value: randomCode,
        editable: true,
        requiredForReview: false,
        confidenceLabel: randomCodeConfidence,
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.sellerName,
        label: '商家名稱',
        value: merchantName,
        editable: true,
        requiredForReview: false,
        confidenceLabel: merchantName.isEmpty
            ? '未辨識'
            : _ocrConfidenceLabel(
                ocr?.confidence[TraditionalInvoiceOcrField.sellerName],
              ),
        warnings: ocr?.fieldWarnings[TraditionalInvoiceOcrField.sellerName] ??
            const <String>[],
      ),
    ];

    final warnings = <String>[
      ...base.warnings,
      if (fieldEvidence.suggestsElectronicInvoice && qrParsed == null)
        '已從「隨機碼」取得電子發票版面證據；QR 不可用時仍以本機 OCR 欄位進行覆核，發票類型不阻擋欄位辨識。',
    ];

    return InvoiceReviewFormViewModel(
      title: base.title,
      routeReason: base.routeReason,
      disclaimer: base.disclaimer,
      fields: List<InvoiceReviewFieldViewModel>.unmodifiable(fields),
      lineItems: base.lineItems,
      warnings: List<String>.unmodifiable(warnings),
      availableOverrides: base.availableOverrides,
      canOpenReview: base.canOpenReview,
      requiresAcknowledgement: base.requiresAcknowledgement,
      disclaimerAcknowledged: base.disclaimerAcknowledged,
    );
  }

  String _ocrConfidenceLabel(
    TraditionalInvoiceOcrConfidence? confidence, {
    String source = '',
  }) {
    final label = switch (confidence) {
      TraditionalInvoiceOcrConfidence.high => '高',
      TraditionalInvoiceOcrConfidence.medium => '中',
      TraditionalInvoiceOcrConfidence.low => '低',
      TraditionalInvoiceOcrConfidence.unknown || null => '未提供',
    };
    return source.trim().isEmpty ? label : '$label · $source';
  }
}
