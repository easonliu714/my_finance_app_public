import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/daily_capture_entry_shell.dart';
import 'package:my_finance_app/features/invoice/image_capture_staging.dart';
import 'package:my_finance_app/features/invoice/invoice_automatic_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_capture_review_flow.dart';
import 'package:my_finance_app/features/invoice/invoice_local_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_identity_review_service.dart';
import 'package:my_finance_app/features/invoice/invoice_qr_parser.dart';
import 'package:my_finance_app/features/invoice/invoice_recognition_router.dart';
import 'package:my_finance_app/features/invoice/invoice_registry_corroboration_policy.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_view_model.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_ocr_review.dart';
import 'package:my_finance_app/features/merchant/business_registry_repository.dart';
import 'package:my_finance_app/features/merchant/merchant_identity_resolution_policy.dart';
import 'package:my_finance_app/features/merchant/merchant_record.dart';

void main() {
  const policy = InvoiceRegistryCorroborationAuthorityPolicy();

  test('QR seller identifier is eligible without checksum promotion', () {
    const parsed = InvoiceQrParseResult(
      rawPayload: 'fixture',
      invoiceNumber: 'AB12345678',
      invoiceDate: null,
      totalAmount: 110,
      sellerIdentifier: '60744698',
      errors: <String>[],
      warnings: <String>[],
    );
    const routing = InvoiceRecognitionRoutingResult(
      route: InvoiceRecognitionRoute.electronicInvoiceQr,
      message: 'fixture',
      pairs: <InvoiceQrPairCandidate>[
        InvoiceQrPairCandidate(
          left: InvoiceQrPayloadEvidence(
            imageReference: 'fixture.jpg',
            fileName: 'fixture.jpg',
            rawPayload: 'fixture',
            role: InvoiceQrPayloadRole.left,
            leftParseResult: parsed,
          ),
        ),
      ],
    );
    const recognition = InvoiceAutomaticRecognitionResult(
      status: InvoiceAutomaticRecognitionStatus.qrReviewCandidate,
      message: 'fixture',
      selectedRouteReason: 'fixture',
      requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
      qrResult: InvoiceLocalRecognitionResult(
        status: InvoiceLocalRecognitionStatus.qrCandidate,
        message: 'fixture',
        failedImageReferences: <String>[],
        routingResult: routing,
      ),
    );
    final review = _review(sellerTaxId: '60744698');

    final decision = policy.evaluate(
      recognition: recognition,
      review: review,
    );

    expect(decision.authoritative, isTrue);
    expect(decision.source, InvoiceRegistryCorroborationAuthoritySource.qrPayload);
  });

  test('Traditional Frozen explicit-label seller identifier is eligible', () {
    final recognition = _ocrRecognition(
      sellerTaxId: '30340553',
      sellerTaxIdSource: 'explicit_label',
    );

    final decision = policy.evaluate(
      recognition: recognition,
      review: _review(sellerTaxId: '30340553'),
    );

    expect(decision.authoritative, isTrue);
    expect(
      decision.source,
      InvoiceRegistryCorroborationAuthoritySource.traditionalExplicitLabel,
    );
  });

  test('weak OCR source cannot gain authority through registry eligibility', () {
    final recognition = _ocrRecognition(
      sellerTaxId: '30340553',
      sellerTaxIdSource: 'contextual_no_header',
    );

    final decision = policy.evaluate(
      recognition: recognition,
      review: _review(sellerTaxId: '30340553'),
    );

    expect(decision.authoritative, isFalse);
    expect(decision.source, InvoiceRegistryCorroborationAuthoritySource.none);
  });

  test('authoritative OCR lookup enriches review without replacing literal merchant',
      () async {
    final fakeIdentity = _FakeIdentityReviewPort();
    final coordinator = InvoiceCaptureReviewFlowCoordinator(
      recognitionCoordinator: InvoiceAutomaticRecognitionCoordinator(
        qrRunner: ({required images, required mode}) async =>
            throw StateError('QR runner must not execute in OCR-only fixture'),
        ocrRunner: (_) async => TraditionalInvoiceOcrResult(
          status: TraditionalInvoiceOcrStatus.success,
          message: 'fixture',
          candidate: _ocrCandidate(
            sellerTaxId: '30340553',
            sellerTaxIdSource: 'explicit_label',
            sellerName: '發票原文商家',
          ),
        ),
      ),
      merchantIdentityReviewService: fakeIdentity,
    );

    final result = await coordinator.recognize(
      image: _image(),
      requestedRoute: InvoiceRecognitionRequestedRoute.traditionalInvoiceOcr,
    );

    expect(fakeIdentity.resolveCalls, 1);
    expect(result.registryAuthorityDecision?.authoritative, isTrue);
    expect(result.registryContext?.registryStatus, BusinessRegistryLookupStatus.hit);
    final sellerName = result.formModel.fieldFor(InvoiceReviewFieldKey.sellerName)!;
    expect(sellerName.value, '發票原文商家');
    expect(
      sellerName.warnings.join('|'),
      contains('官方登記名稱：一品現泡茶店'),
    );
    expect(sellerName.warnings.join('|'), contains('實機驗證子集'));
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('non-authoritative OCR performs zero registry calls', () async {
    final fakeIdentity = _FakeIdentityReviewPort();
    final coordinator = InvoiceCaptureReviewFlowCoordinator(
      recognitionCoordinator: InvoiceAutomaticRecognitionCoordinator(
        qrRunner: ({required images, required mode}) async =>
            throw StateError('QR runner must not execute in OCR-only fixture'),
        ocrRunner: (_) async => TraditionalInvoiceOcrResult(
          status: TraditionalInvoiceOcrStatus.success,
          message: 'fixture',
          candidate: _ocrCandidate(
            sellerTaxId: '30340553',
            sellerTaxIdSource: 'contextual_no_header',
            sellerName: '發票原文商家',
          ),
        ),
      ),
      merchantIdentityReviewService: fakeIdentity,
    );

    final result = await coordinator.recognize(
      image: _image(),
      requestedRoute: InvoiceRecognitionRequestedRoute.traditionalInvoiceOcr,
    );

    expect(fakeIdentity.resolveCalls, 0);
    expect(result.registryContext, isNull);
    expect(result.registryAuthorityDecision?.authoritative, isFalse);
  });
}

InvoiceAutomaticRecognitionResult _ocrRecognition({
  required String sellerTaxId,
  required String sellerTaxIdSource,
}) {
  return InvoiceAutomaticRecognitionResult(
    status: InvoiceAutomaticRecognitionStatus.ocrReviewCandidate,
    message: 'fixture',
    selectedRouteReason: 'fixture',
    requestedRoute: InvoiceRecognitionRequestedRoute.traditionalInvoiceOcr,
    ocrResult: TraditionalInvoiceOcrResult(
      status: TraditionalInvoiceOcrStatus.success,
      message: 'fixture',
      candidate: _ocrCandidate(
        sellerTaxId: sellerTaxId,
        sellerTaxIdSource: sellerTaxIdSource,
        sellerName: '發票原文商家',
      ),
    ),
  );
}

TraditionalInvoiceOcrReviewCandidate _ocrCandidate({
  required String sellerTaxId,
  required String sellerTaxIdSource,
  required String sellerName,
}) {
  return TraditionalInvoiceOcrReviewCandidate(
    sourceImageReference: 'fixture.jpg',
    invoiceNumber: 'AB12345678',
    sellerTaxId: sellerTaxId,
    sellerTaxIdSource: sellerTaxIdSource,
    invoiceDate: DateTime(2026, 8, 31),
    sellerName: sellerName,
    totalAmount: 110,
    visibleLineItems: const <TraditionalInvoiceOcrLineItem>[],
    confidence: const <TraditionalInvoiceOcrField, TraditionalInvoiceOcrConfidence>{
      TraditionalInvoiceOcrField.invoiceNumber: TraditionalInvoiceOcrConfidence.high,
      TraditionalInvoiceOcrField.sellerTaxId: TraditionalInvoiceOcrConfidence.high,
      TraditionalInvoiceOcrField.invoiceDate: TraditionalInvoiceOcrConfidence.high,
      TraditionalInvoiceOcrField.sellerName: TraditionalInvoiceOcrConfidence.medium,
      TraditionalInvoiceOcrField.totalAmount: TraditionalInvoiceOcrConfidence.high,
    },
    fieldWarnings: const <TraditionalInvoiceOcrField, List<String>>{},
  );
}

InvoiceReviewFormViewModel _review({required String sellerTaxId}) {
  return InvoiceReviewFormViewModel(
    title: 'fixture',
    routeReason: 'fixture',
    disclaimer: 'fixture',
    fields: <InvoiceReviewFieldViewModel>[
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.sellerTaxId,
        label: '賣方統編',
        value: sellerTaxId,
        editable: true,
        requiredForReview: true,
      ),
    ],
    lineItems: const <InvoiceReviewLineItemViewModel>[],
    warnings: const <String>[],
    availableOverrides: const [],
    canOpenReview: true,
    requiresAcknowledgement: false,
    disclaimerAcknowledged: false,
  );
}

ImageCaptureStagingItem _image() {
  return ImageCaptureStagingItem(
    id: 'fixture',
    intent: DailyCaptureIntent.invoice,
    source: ImageCaptureStagingSource.gallery,
    localReference: 'fixture.jpg',
    fileName: 'fixture.jpg',
    status: ImageCaptureStagingStatus.pendingReview,
    createdAt: DateTime(2026, 8, 31),
  );
}

class _FakeIdentityReviewPort implements InvoiceMerchantIdentityReviewPort {
  int resolveCalls = 0;

  @override
  Future<InvoiceMerchantIdentityReviewContext> resolve({
    required String sellerIdentifier,
    required bool sellerIdentifierAuthoritative,
    required String literalMerchantText,
  }) async {
    resolveCalls += 1;
    return InvoiceMerchantIdentityReviewContext(
      decision: MerchantIdentityResolutionDecision(
        literalMerchantText: literalMerchantText,
        sellerIdentifier: sellerIdentifier,
        registryLookupAllowed: true,
        officialLegalNameSuggestion: '一品現泡茶店',
        formalMerchantName: '',
        requiresBrandConfirmation: true,
        reason: MerchantIdentityResolutionReason.registryLegalNameNeedsBrandConfirmation,
      ),
      registryStatus: BusinessRegistryLookupStatus.hit,
      registryVersion: 'fixture-v1',
      registryCoverage: 'validation_subset',
      registrySourceDataDate: '2025-06-02',
    );
  }

  @override
  Future<InvoiceMerchantIdentityReviewContext> confirmBinding({
    required MerchantRecord merchant,
    required String sellerIdentifier,
    required String literalMerchantText,
    required String evidenceSource,
    required String sourceReference,
  }) {
    throw UnimplementedError();
  }
}
