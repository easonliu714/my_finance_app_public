enum CloudInvoiceCandidateSource {
  manualEntry,
  invoiceQrCode,
  mockCloudInvoice,
  receiptOcr,
  privateCloudResearch,
}

class CloudInvoiceCandidateSourceMetadata {
  const CloudInvoiceCandidateSourceMetadata({
    required this.label,
    required this.shortLabel,
    required this.isPublicReleaseSafe,
    required this.isPrivateResearchOnly,
    required this.supportsAutomaticBackgroundSync,
  });

  final String label;
  final String shortLabel;
  final bool isPublicReleaseSafe;
  final bool isPrivateResearchOnly;
  final bool supportsAutomaticBackgroundSync;
}

extension CloudInvoiceCandidateSourceMetadataX on CloudInvoiceCandidateSource {
  CloudInvoiceCandidateSourceMetadata get metadata {
    switch (this) {
      case CloudInvoiceCandidateSource.manualEntry:
        return const CloudInvoiceCandidateSourceMetadata(
          label: '手動輸入',
          shortLabel: '手動',
          isPublicReleaseSafe: true,
          isPrivateResearchOnly: false,
          supportsAutomaticBackgroundSync: false,
        );
      case CloudInvoiceCandidateSource.invoiceQrCode:
        return const CloudInvoiceCandidateSourceMetadata(
          label: 'QR Code 離線解析',
          shortLabel: 'QR',
          isPublicReleaseSafe: true,
          isPrivateResearchOnly: false,
          supportsAutomaticBackgroundSync: false,
        );
      case CloudInvoiceCandidateSource.mockCloudInvoice:
        return const CloudInvoiceCandidateSourceMetadata(
          label: '模擬雲端發票',
          shortLabel: '模擬雲端',
          isPublicReleaseSafe: true,
          isPrivateResearchOnly: false,
          supportsAutomaticBackgroundSync: false,
        );
      case CloudInvoiceCandidateSource.receiptOcr:
        return const CloudInvoiceCandidateSourceMetadata(
          label: '拍照辨識候選',
          shortLabel: 'OCR',
          isPublicReleaseSafe: false,
          isPrivateResearchOnly: false,
          supportsAutomaticBackgroundSync: false,
        );
      case CloudInvoiceCandidateSource.privateCloudResearch:
        return const CloudInvoiceCandidateSourceMetadata(
          label: '私有雲端實驗',
          shortLabel: '私有實驗',
          isPublicReleaseSafe: false,
          isPrivateResearchOnly: true,
          supportsAutomaticBackgroundSync: false,
        );
    }
  }
}

enum CloudInvoiceCandidateStatus {
  pending,
  duplicate,
  rejected,
  retryableError,
  confirmedDraft,
  discarded,
  blocked,
}

enum CloudInvoiceCandidateWarning {
  missingSellerName,
  missingLineItems,
  partialPayload,
  lowConfidence,
}

enum CloudInvoiceCandidateErrorCategory {
  none,
  parseError,
  authorization,
  network,
  rateLimited,
  unsupportedCarrier,
  policyBlocked,
}

class CloudInvoiceLineItem {
  const CloudInvoiceLineItem({
    required this.name,
    required this.amount,
    this.quantity,
    this.unitPrice,
    this.rawName,
    this.categorySuggestion,
  });

  final String name;
  final double amount;
  final double? quantity;
  final double? unitPrice;
  final String? rawName;
  final String? categorySuggestion;

  bool get hasCategorySuggestion => categorySuggestion != null && categorySuggestion!.trim().isNotEmpty;
}

class CloudInvoiceCandidate {
  const CloudInvoiceCandidate({
    required this.source,
    required this.status,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.sellerIdentifier,
    required this.sellerName,
    required this.totalAmount,
    required this.carrierType,
    required this.carrierMaskedId,
    required this.fetchedAt,
    this.taxAmount,
    this.buyerIdentifier,
    this.lineItems = const <CloudInvoiceLineItem>[],
    this.rawPayload,
    this.confidence,
    this.warnings = const <CloudInvoiceCandidateWarning>[],
    this.errorCategory = CloudInvoiceCandidateErrorCategory.none,
    this.errorMessage,
    this.duplicateKeyOverride,
  });

  final CloudInvoiceCandidateSource source;
  final CloudInvoiceCandidateStatus status;
  final String invoiceNumber;
  final DateTime invoiceDate;
  final String sellerIdentifier;
  final String sellerName;
  final double totalAmount;
  final double? taxAmount;
  final String? buyerIdentifier;
  final String carrierType;
  final String carrierMaskedId;
  final DateTime fetchedAt;
  final List<CloudInvoiceLineItem> lineItems;
  final String? rawPayload;
  final double? confidence;
  final List<CloudInvoiceCandidateWarning> warnings;
  final CloudInvoiceCandidateErrorCategory errorCategory;
  final String? errorMessage;
  final String? duplicateKeyOverride;

  bool get requiresUserReview => status == CloudInvoiceCandidateStatus.pending || status == CloudInvoiceCandidateStatus.duplicate;
  bool get canCreateFormalTransactionAutomatically => false;
  bool get canWriteMerchantAutomatically => false;
  bool get canWriteAccountAutomatically => false;
  bool get hasLineItems => lineItems.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
  bool get hasError => errorCategory != CloudInvoiceCandidateErrorCategory.none;
  bool get isRetryable => status == CloudInvoiceCandidateStatus.retryableError;
  bool get isRejected => status == CloudInvoiceCandidateStatus.rejected;
  bool get isPublicReleaseSafeSource => source.metadata.isPublicReleaseSafe;
  bool get isPrivateResearchSource => source.metadata.isPrivateResearchOnly;
  bool get supportsAutomaticBackgroundSync => source.metadata.supportsAutomaticBackgroundSync;
  String get sourceLabel => source.metadata.label;
  String get sourceShortLabel => source.metadata.shortLabel;

  String get displaySellerName {
    final trimmed = sellerName.trim();
    return trimmed.isEmpty ? '未命名雲端發票商家' : trimmed;
  }

  String get safeCarrierDisplay {
    final trimmed = carrierMaskedId.trim();
    if (trimmed.isEmpty) return '已遮罩載具';
    if (trimmed.length <= 4) return '****';
    return trimmed;
  }

  String get duplicateKey {
    final override = duplicateKeyOverride?.trim();
    if (override != null && override.isNotEmpty) return override.toUpperCase();
    final normalizedInvoice = invoiceNumber.trim().toUpperCase();
    final normalizedSeller = sellerIdentifier.trim().toUpperCase();
    final roundedAmount = totalAmount.toStringAsFixed(0);
    return '$normalizedInvoice|${_dateKey(invoiceDate)}|$roundedAmount|$normalizedSeller';
  }

  CloudInvoiceCandidate copyWith({
    CloudInvoiceCandidateSource? source,
    CloudInvoiceCandidateStatus? status,
    String? invoiceNumber,
    DateTime? invoiceDate,
    String? sellerIdentifier,
    String? sellerName,
    double? totalAmount,
    double? taxAmount,
    bool clearTaxAmount = false,
    String? buyerIdentifier,
    bool clearBuyerIdentifier = false,
    String? carrierType,
    String? carrierMaskedId,
    DateTime? fetchedAt,
    List<CloudInvoiceLineItem>? lineItems,
    String? rawPayload,
    bool clearRawPayload = false,
    double? confidence,
    bool clearConfidence = false,
    List<CloudInvoiceCandidateWarning>? warnings,
    CloudInvoiceCandidateErrorCategory? errorCategory,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? duplicateKeyOverride,
    bool clearDuplicateKeyOverride = false,
  }) {
    return CloudInvoiceCandidate(
      source: source ?? this.source,
      status: status ?? this.status,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      sellerIdentifier: sellerIdentifier ?? this.sellerIdentifier,
      sellerName: sellerName ?? this.sellerName,
      totalAmount: totalAmount ?? this.totalAmount,
      taxAmount: clearTaxAmount ? null : (taxAmount ?? this.taxAmount),
      buyerIdentifier: clearBuyerIdentifier ? null : (buyerIdentifier ?? this.buyerIdentifier),
      carrierType: carrierType ?? this.carrierType,
      carrierMaskedId: carrierMaskedId ?? this.carrierMaskedId,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      lineItems: lineItems ?? this.lineItems,
      rawPayload: clearRawPayload ? null : (rawPayload ?? this.rawPayload),
      confidence: clearConfidence ? null : (confidence ?? this.confidence),
      warnings: warnings ?? this.warnings,
      errorCategory: errorCategory ?? this.errorCategory,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      duplicateKeyOverride: clearDuplicateKeyOverride ? null : (duplicateKeyOverride ?? this.duplicateKeyOverride),
    );
  }

  static String _dateKey(DateTime value) {
    String twoDigits(int input) => input.toString().padLeft(2, '0');
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)}';
  }
}
