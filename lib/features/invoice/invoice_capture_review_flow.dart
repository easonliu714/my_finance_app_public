import 'image_capture_staging.dart';
import 'invoice_automatic_recognition_coordinator.dart';
import 'invoice_registry_corroboration_policy.dart';
import 'invoice_review_form_view_model.dart';
import 'invoice_review_handoff_contract.dart';
import 'invoice_review_qr_line_item_enricher.dart';

class InvoiceCaptureReviewFlowResult {
  const InvoiceCaptureReviewFlowResult({
    required this.recognitionResult,
    required this.handoffState,
    required this.formModel,
    this.registryAuthorityDecision,
  });

  final InvoiceAutomaticRecognitionResult recognitionResult;
  final InvoiceReviewHandoffState handoffState;
  final InvoiceReviewFormViewModel formModel;
  final InvoiceRegistryCorroborationAuthorityDecision? registryAuthorityDecision;

  bool get canOpenReview => formModel.canOpenReview;
  bool get canCreateFormalRecord => false;
  bool get usedNetwork => false;

  Map<String, Object?> toSafeSummary() {
    return <String, Object?>{
      'recognitionStatus': recognitionResult.status.name,
      'handoffAction': handoffState.action.name,
      'canOpenReview': canOpenReview,
      'canCreateFormalRecord': canCreateFormalRecord,
      'usedNetwork': usedNetwork,
      'form': formModel.toSafeSummary(),
      'registryLookupEligible': registryAuthorityDecision?.authoritative == true,
      'registryAuthoritySource': registryAuthorityDecision?.source.name ?? 'none',
      // Actual registry access belongs to the mutable review surface, because
      // sellerTaxId/source may still be changed by the user or AI selection.
      'registryLookupOwner': 'transaction_handoff_review',
    };
  }
}

class InvoiceCaptureReviewFlowCoordinator {
  const InvoiceCaptureReviewFlowCoordinator({
    required this.recognitionCoordinator,
    this.handoffPresenter = const InvoiceReviewHandoffPresenter(),
    this.formPresenter = const InvoiceReviewFormPresenter(),
    this.qrLineItemEnricher = const InvoiceReviewQrLineItemEnricher(),
    this.registryAuthorityPolicy =
        const InvoiceRegistryCorroborationAuthorityPolicy(),
  });

  final InvoiceAutomaticRecognitionCoordinator recognitionCoordinator;
  final InvoiceReviewHandoffPresenter handoffPresenter;
  final InvoiceReviewFormPresenter formPresenter;
  final InvoiceReviewQrLineItemEnricher qrLineItemEnricher;
  final InvoiceRegistryCorroborationAuthorityPolicy registryAuthorityPolicy;

  Future<InvoiceCaptureReviewFlowResult> recognize({
    required ImageCaptureStagingItem image,
    required InvoiceRecognitionRequestedRoute requestedRoute,
  }) async {
    final recognitionResult = await recognitionCoordinator.recognize(
      images: <ImageCaptureStagingItem>[image],
      requestedRoute: requestedRoute,
    );
    final handoffState = handoffPresenter.fromAutomaticResult(
      recognitionResult,
    );
    final baseFormModel = formPresenter.fromHandoff(handoffState);
    final formModel = qrLineItemEnricher.enrich(
      review: baseFormModel,
      recognition: recognitionResult,
    );

    // Only freeze the recognition-time authority decision here. The review
    // card is the single owner of actual registry lookup/refresh because the
    // seller ID and its source may change after OCR/QR through user or AI
    // review. This prevents duplicate refreshes and stale corroboration.
    final authorityDecision = registryAuthorityPolicy.evaluate(
      recognition: recognitionResult,
      review: formModel,
    );

    return InvoiceCaptureReviewFlowResult(
      recognitionResult: recognitionResult,
      handoffState: handoffState,
      formModel: formModel,
      registryAuthorityDecision: authorityDecision,
    );
  }
}
