import 'cloud_invoice_candidate.dart';

enum CloudInvoiceMockScenario {
  validMinimal,
  validWithItems,
  partialPayload,
  malformedPayload,
  duplicateInvoice,
  unauthorized,
  expiredAuthorization,
  networkUnavailable,
  rateLimited,
  unsupportedCarrier,
}

class CloudInvoiceMockProviderResult {
  const CloudInvoiceMockProviderResult._({
    required this.candidates,
    required this.errorCategory,
    required this.retryable,
    this.message,
  });

  factory CloudInvoiceMockProviderResult.success(List<CloudInvoiceCandidate> candidates) {
    return CloudInvoiceMockProviderResult._(
      candidates: List<CloudInvoiceCandidate>.unmodifiable(candidates),
      errorCategory: CloudInvoiceCandidateErrorCategory.none,
      retryable: false,
    );
  }

  factory CloudInvoiceMockProviderResult.failure({
    required CloudInvoiceCandidateErrorCategory errorCategory,
    required String message,
    bool retryable = false,
  }) {
    return CloudInvoiceMockProviderResult._(
      candidates: const <CloudInvoiceCandidate>[],
      errorCategory: errorCategory,
      retryable: retryable,
      message: message,
    );
  }

  final List<CloudInvoiceCandidate> candidates;
  final CloudInvoiceCandidateErrorCategory errorCategory;
  final bool retryable;
  final String? message;

  bool get isSuccess => errorCategory == CloudInvoiceCandidateErrorCategory.none;
  bool get hasCandidates => candidates.isNotEmpty;
  bool get canRetryManually => retryable;
  bool get canScheduleBackgroundRetry => false;
}

class CloudInvoiceMockProvider {
  const CloudInvoiceMockProvider({DateTime Function()? clock}) : _clock = clock;

  final DateTime Function()? _clock;

  CloudInvoiceMockProviderResult fetch(CloudInvoiceMockScenario scenario) {
    switch (scenario) {
      case CloudInvoiceMockScenario.validMinimal:
        return CloudInvoiceMockProviderResult.success(<CloudInvoiceCandidate>[_candidate()]);
      case CloudInvoiceMockScenario.validWithItems:
        return CloudInvoiceMockProviderResult.success(<CloudInvoiceCandidate>[
          _candidate(
            lineItems: const <CloudInvoiceLineItem>[
              CloudInvoiceLineItem(name: '鮮奶', quantity: 1, unitPrice: 95, amount: 95, categorySuggestion: '飲食'),
              CloudInvoiceLineItem(name: '麵包', quantity: 1, unitPrice: 35, amount: 35),
            ],
          ),
        ]);
      case CloudInvoiceMockScenario.partialPayload:
        return CloudInvoiceMockProviderResult.success(<CloudInvoiceCandidate>[
          _candidate(
            sellerName: '',
            warnings: const <CloudInvoiceCandidateWarning>[
              CloudInvoiceCandidateWarning.missingSellerName,
              CloudInvoiceCandidateWarning.missingLineItems,
            ],
          ),
        ]);
      case CloudInvoiceMockScenario.malformedPayload:
        return CloudInvoiceMockProviderResult.success(<CloudInvoiceCandidate>[
          _candidate(
            invoiceNumber: '',
            totalAmount: 0,
            status: CloudInvoiceCandidateStatus.rejected,
            errorCategory: CloudInvoiceCandidateErrorCategory.parseError,
            errorMessage: 'Malformed cloud invoice payload.',
          ),
        ]);
      case CloudInvoiceMockScenario.duplicateInvoice:
        return CloudInvoiceMockProviderResult.success(<CloudInvoiceCandidate>[
          _candidate(status: CloudInvoiceCandidateStatus.duplicate, duplicateKeyOverride: 'AB12345678|2026-06-09|120|12345678'),
        ]);
      case CloudInvoiceMockScenario.unauthorized:
        return CloudInvoiceMockProviderResult.failure(
          errorCategory: CloudInvoiceCandidateErrorCategory.authorization,
          message: 'Authorization is required.',
        );
      case CloudInvoiceMockScenario.expiredAuthorization:
        return CloudInvoiceMockProviderResult.failure(
          errorCategory: CloudInvoiceCandidateErrorCategory.authorization,
          message: 'Authorization has expired.',
        );
      case CloudInvoiceMockScenario.networkUnavailable:
        return CloudInvoiceMockProviderResult.failure(
          errorCategory: CloudInvoiceCandidateErrorCategory.network,
          message: 'Network is unavailable.',
          retryable: true,
        );
      case CloudInvoiceMockScenario.rateLimited:
        return CloudInvoiceMockProviderResult.failure(
          errorCategory: CloudInvoiceCandidateErrorCategory.rateLimited,
          message: 'Rate limit reached.',
          retryable: true,
        );
      case CloudInvoiceMockScenario.unsupportedCarrier:
        return CloudInvoiceMockProviderResult.failure(
          errorCategory: CloudInvoiceCandidateErrorCategory.unsupportedCarrier,
          message: 'Carrier is unsupported.',
        );
    }
  }

  CloudInvoiceCandidate _candidate({
    CloudInvoiceCandidateStatus status = CloudInvoiceCandidateStatus.pending,
    String invoiceNumber = 'AB12345678',
    DateTime? invoiceDate,
    String sellerIdentifier = '12345678',
    String sellerName = '全家便利商店',
    double totalAmount = 120,
    List<CloudInvoiceLineItem> lineItems = const <CloudInvoiceLineItem>[],
    List<CloudInvoiceCandidateWarning> warnings = const <CloudInvoiceCandidateWarning>[],
    CloudInvoiceCandidateErrorCategory errorCategory = CloudInvoiceCandidateErrorCategory.none,
    String? errorMessage,
    String? duplicateKeyOverride,
  }) {
    return CloudInvoiceCandidate(
      source: CloudInvoiceCandidateSource.mockCloudInvoice,
      status: status,
      invoiceNumber: invoiceNumber,
      invoiceDate: invoiceDate ?? DateTime(2026, 6, 9),
      sellerIdentifier: sellerIdentifier,
      sellerName: sellerName,
      totalAmount: totalAmount,
      taxAmount: 6,
      carrierType: 'mobileBarcode',
      carrierMaskedId: '/AB***12',
      fetchedAt: (_clock ?? () => DateTime.utc(2026, 6, 10, 8)).call(),
      lineItems: lineItems,
      rawPayload: 'mock-cloud-invoice-payload',
      warnings: warnings,
      errorCategory: errorCategory,
      errorMessage: errorMessage,
      duplicateKeyOverride: duplicateKeyOverride,
    );
  }
}
