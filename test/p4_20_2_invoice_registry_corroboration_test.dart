import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/daily_capture_entry_shell.dart';
import 'package:my_finance_app/features/invoice/image_capture_staging.dart';
import 'package:my_finance_app/features/invoice/invoice_automatic_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_capture_review_flow.dart';
import 'package:my_finance_app/features/invoice/invoice_local_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_qr_parser.dart';
import 'package:my_finance_app/features/invoice/invoice_recognition_router.dart';
import 'package:my_finance_app/features/invoice/invoice_registry_corroboration_policy.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_view_model.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_ocr_review.dart';
import 'package:my_finance_app/features/invoice/traditional_tax_id_temporal_repair.dart';

void main() {
  const policy = InvoiceRegistryCorroborationAuthorityPolicy();

  test('QR seller identifier is eligible without checksum promotion', () {
    const parsed = InvoiceQrParseResult(
      rawPayload: 'fixture',
      invoiceNumber: 'AB12345678',
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

    final decision = policy.evaluate(
      recognition: recognition,
      review: _review(
        sellerTaxId: '60744698',
        sellerTaxIdSource: InvoiceRegistryCorroborationAuthorityPolicy.qrPayloadSource,
      ),
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
      review: _review(
        sellerTaxId: '30340553',
        sellerTaxIdSource: 'explicit_label',
      ),
    );

    expect(decision.authoritative, isTrue);
    expect(
      decision.source,
      InvoiceRegistryCorroborationAuthoritySource.traditionalExplicitLabel,
    );
  });

  test('Live temporal seller-id repair is governed local authority', () {
    final recognition = _ocrRecognition(
      sellerTaxId: '30340553',
      sellerTaxIdSource: positionalTaxIdTemporalRepairSource,
    );

    final decision = policy.evaluate(
      recognition: recognition,
      review: _review(
        sellerTaxId: '30340553',
        sellerTaxIdSource: positionalTaxIdTemporalRepairSource,
      ),
    );

    expect(decision.authoritative, isTrue);
    expect(
      decision.source,
      InvoiceRegistryCorroborationAuthoritySource.governedLocalEvidence,
    );
    expect(decision.reason, 'authoritative_temporal_seller_identifier_repair');
  });

  test('weak OCR source cannot gain authority through registry eligibility', () {
    final recognition = _ocrRecognition(
      sellerTaxId: '30340553',
      sellerTaxIdSource: 'contextual_no_header',
    );

    final decision = policy.evaluate(
      recognition: recognition,
      review: _review(
        sellerTaxId: '30340553',
        sellerTaxIdSource: 'contextual_no_header',
      ),
    );

    expect(decision.authoritative, isFalse);
    expect(decision.source, InvoiceRegistryCorroborationAuthoritySource.none);
  });

  test('checksum-valid initial value without provenance stays fail closed', () {
    final decision = policy.evaluateReviewSelection(
      sellerIdentifier: '30340553',
      localQrAuthority: false,
      explicitlyCorrected: false,
      explicitlyAiSelected: false,
      aiComparisonAcknowledged: false,
      initialLocalSellerIdentifierSource: '',
    );

    expect(decision.authoritative, isFalse);
    expect(decision.reason, 'review_selection_not_authoritative');
  });

  test('explicit and temporal Local provenance survive review re-evaluation', () {
    final explicit = policy.evaluateReviewSelection(
      sellerIdentifier: '30340553',
      localQrAuthority: false,
      explicitlyCorrected: false,
      explicitlyAiSelected: false,
      aiComparisonAcknowledged: false,
      initialLocalSellerIdentifierSource: 'explicit_label',
    );
    expect(explicit.authoritative, isTrue);
    expect(
      explicit.source,
      InvoiceRegistryCorroborationAuthoritySource.traditionalExplicitLabel,
    );

    final temporal = policy.evaluateReviewSelection(
      sellerIdentifier: '30340553',
      localQrAuthority: false,
      explicitlyCorrected: false,
      explicitlyAiSelected: false,
      aiComparisonAcknowledged: false,
      initialLocalSellerIdentifierSource: positionalTaxIdTemporalRepairSource,
    );
    expect(temporal.authoritative, isTrue);
    expect(
      temporal.source,
      InvoiceRegistryCorroborationAuthoritySource.governedLocalEvidence,
    );
  });

  test('explicit AI seller id requires acknowledgement and strict checksum', () {
    final beforeAck = policy.evaluateReviewSelection(
      sellerIdentifier: '30340553',
      localQrAuthority: false,
      explicitlyCorrected: false,
      explicitlyAiSelected: true,
      aiComparisonAcknowledged: false,
      initialLocalSellerIdentifierSource: '',
    );
    expect(beforeAck.authoritative, isFalse);
    expect(beforeAck.reason, 'ai_selection_not_globally_acknowledged');

    final accepted = policy.evaluateReviewSelection(
      sellerIdentifier: '30340553',
      localQrAuthority: false,
      explicitlyCorrected: false,
      explicitlyAiSelected: true,
      aiComparisonAcknowledged: true,
      initialLocalSellerIdentifierSource: '',
    );
    expect(accepted.authoritative, isTrue);
    expect(
      accepted.source,
      InvoiceRegistryCorroborationAuthoritySource.explicitAiSelection,
    );

    final invalidChecksum = policy.evaluateReviewSelection(
      sellerIdentifier: '60744698',
      localQrAuthority: false,
      explicitlyCorrected: false,
      explicitlyAiSelected: true,
      aiComparisonAcknowledged: true,
      initialLocalSellerIdentifierSource: '',
    );
    expect(invalidChecksum.authoritative, isFalse);
    expect(invalidChecksum.reason, 'ai_selection_failed_strict_checksum');
  });

  test('manual correction uses strict non-QR seller-id validation', () {
    final accepted = policy.evaluateReviewSelection(
      sellerIdentifier: '30340553',
      localQrAuthority: false,
      explicitlyCorrected: true,
      explicitlyAiSelected: false,
      aiComparisonAcknowledged: false,
      initialLocalSellerIdentifierSource: '',
    );
    expect(accepted.authoritative, isTrue);
    expect(
      accepted.source,
      InvoiceRegistryCorroborationAuthoritySource.explicitUserCorrection,
    );

    final rejected = policy.evaluateReviewSelection(
      sellerIdentifier: '60744698',
      localQrAuthority: false,
      explicitlyCorrected: true,
      explicitlyAiSelected: false,
      aiComparisonAcknowledged: false,
      initialLocalSellerIdentifierSource: '',
    );
    expect(rejected.authoritative, isFalse);
  });

  test('capture coordinator freezes authority only and performs no registry I/O',
      () async {
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
    );

    final result = await coordinator.recognize(
      image: _image(),
      requestedRoute: InvoiceRecognitionRequestedRoute.traditionalInvoiceOcr,
    );

    expect(result.registryAuthorityDecision?.authoritative, isTrue);
    expect(result.formModel.sellerTaxIdSource, 'explicit_label');
    expect(result.formModel.fieldFor(InvoiceReviewFieldKey.sellerName)?.value,
        '發票原文商家');
    expect(result.canCreateFormalRecord, isFalse);
    expect(result.toSafeSummary()['registryLookupOwner'],
        'transaction_handoff_review');
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

InvoiceReviewFormViewModel _review({
  required String sellerTaxId,
  String sellerTaxIdSource = '',
}) {
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
    sellerTaxIdSource: sellerTaxIdSource,
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
