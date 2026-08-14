enum InvoiceAiVisionUseCase {
  productItemRecognition,
  productReferencePriceEstimation,
  invoiceQrParsing,
  invoiceTextNumberRecognition,
  invoicePrintedContentRecognition,
}

enum InvoiceAiVisionDataPath {
  localOnlyQrParser,
  externalGeminiVision,
}

enum InvoiceAiVisionApiKeyCustody {
  notRequired,
  userProvidedRuntimeOnly,
  secureRuntimeConfig,
  hardcodedInSource,
  committedToRepository,
}

enum InvoiceAiVisionPolicyDecision {
  allowed,
  blocked,
  requiresUserConsent,
}

class InvoiceAiVisionPolicyResult {
  const InvoiceAiVisionPolicyResult({
    required this.useCase,
    required this.dataPath,
    required this.apiKeyCustody,
    required this.decision,
    required this.reason,
    this.requiresReviewGate = true,
    this.outputsAreAdvisory = true,
    this.allowsAutomaticTransactionCreation = false,
  });

  final InvoiceAiVisionUseCase useCase;
  final InvoiceAiVisionDataPath dataPath;
  final InvoiceAiVisionApiKeyCustody apiKeyCustody;
  final InvoiceAiVisionPolicyDecision decision;
  final String reason;
  final bool requiresReviewGate;
  final bool outputsAreAdvisory;
  final bool allowsAutomaticTransactionCreation;

  bool get isAllowed => decision == InvoiceAiVisionPolicyDecision.allowed;
  bool get isBlocked => decision == InvoiceAiVisionPolicyDecision.blocked;
  bool get requiresUserConsent => decision == InvoiceAiVisionPolicyDecision.requiresUserConsent;
}

class InvoiceAiVisionPolicyService {
  const InvoiceAiVisionPolicyService();

  InvoiceAiVisionPolicyResult evaluate({
    required InvoiceAiVisionUseCase useCase,
    required InvoiceAiVisionDataPath dataPath,
    required InvoiceAiVisionApiKeyCustody apiKeyCustody,
    required bool externalImageAnalysisConsentAcknowledged,
  }) {
    if (apiKeyCustody == InvoiceAiVisionApiKeyCustody.hardcodedInSource ||
        apiKeyCustody == InvoiceAiVisionApiKeyCustody.committedToRepository) {
      return InvoiceAiVisionPolicyResult(
        useCase: useCase,
        dataPath: dataPath,
        apiKeyCustody: apiKeyCustody,
        decision: InvoiceAiVisionPolicyDecision.blocked,
        reason: InvoiceAiVisionPolicyCopy.apiKeyCustodyBlocked,
      );
    }

    if (dataPath == InvoiceAiVisionDataPath.localOnlyQrParser) {
      if (useCase != InvoiceAiVisionUseCase.invoiceQrParsing) {
        return InvoiceAiVisionPolicyResult(
          useCase: useCase,
          dataPath: dataPath,
          apiKeyCustody: apiKeyCustody,
          decision: InvoiceAiVisionPolicyDecision.blocked,
          reason: InvoiceAiVisionPolicyCopy.localQrParserOnlySupportsQr,
        );
      }
      return InvoiceAiVisionPolicyResult(
        useCase: useCase,
        dataPath: dataPath,
        apiKeyCustody: InvoiceAiVisionApiKeyCustody.notRequired,
        decision: InvoiceAiVisionPolicyDecision.allowed,
        reason: InvoiceAiVisionPolicyCopy.localQrParserAllowed,
      );
    }

    if (!externalImageAnalysisConsentAcknowledged) {
      return InvoiceAiVisionPolicyResult(
        useCase: useCase,
        dataPath: dataPath,
        apiKeyCustody: apiKeyCustody,
        decision: InvoiceAiVisionPolicyDecision.requiresUserConsent,
        reason: InvoiceAiVisionPolicyCopy.externalImageConsentRequired,
      );
    }

    return InvoiceAiVisionPolicyResult(
      useCase: useCase,
      dataPath: dataPath,
      apiKeyCustody: apiKeyCustody,
      decision: InvoiceAiVisionPolicyDecision.allowed,
      reason: _allowedReason(useCase),
    );
  }

  static String _allowedReason(InvoiceAiVisionUseCase useCase) {
    switch (useCase) {
      case InvoiceAiVisionUseCase.productItemRecognition:
        return InvoiceAiVisionPolicyCopy.productRecognitionAllowed;
      case InvoiceAiVisionUseCase.productReferencePriceEstimation:
        return InvoiceAiVisionPolicyCopy.referencePriceAllowed;
      case InvoiceAiVisionUseCase.invoiceQrParsing:
        return InvoiceAiVisionPolicyCopy.geminiQrAnalysisAllowed;
      case InvoiceAiVisionUseCase.invoiceTextNumberRecognition:
        return InvoiceAiVisionPolicyCopy.invoiceNumberVisionAllowed;
      case InvoiceAiVisionUseCase.invoicePrintedContentRecognition:
        return InvoiceAiVisionPolicyCopy.invoiceContentVisionAllowed;
    }
  }
}

class InvoiceAiVisionPolicyCopy {
  const InvoiceAiVisionPolicyCopy._();

  static const String recommendedModelAlias = 'gemini-flash-latest';
  static const String productRecognitionAllowed = '商品辨識採 Gemini Vision 圖像理解，輸出品項名稱候選，不視為單純 OCR。';
  static const String referencePriceAllowed = '參考價格由 Gemini Vision 產生建議值，只能作為輔助資訊，需使用者確認。';
  static const String localQrParserAllowed = '電子紙 QR code 可先以本機 parser 解析，結果仍需進入候選檢查。';
  static const String geminiQrAnalysisAllowed = 'Gemini 可輔助判讀發票影像中的 QR 區域，但不得自動建立交易。';
  static const String invoiceNumberVisionAllowed = 'Gemini 可辨識文字型發票號碼，結果需使用者確認。';
  static const String invoiceContentVisionAllowed = 'Gemini 可分析發票上記載的店家、日期、金額與品項內容，結果需進入 staging / draft review。';
  static const String externalImageConsentRequired = '影像送出裝置前必須取得使用者同意。';
  static const String apiKeyCustodyBlocked = 'API key 不可硬編在 source，也不可提交到 repository。';
  static const String localQrParserOnlySupportsQr = 'local-only QR parser 不適用於商品辨識、參考價格或印刷文字內容分析。';
  static const String reviewGateRequired = 'AI 辨識結果只能作為候選資料，不可自動建立正式交易。';

  static const List<String> defaultGuardrails = <String>[
    externalImageConsentRequired,
    apiKeyCustodyBlocked,
    reviewGateRequired,
  ];
}
