import 'image_capture_staging.dart';
import 'invoice_automatic_recognition_coordinator.dart';
import 'invoice_review_form_view_model.dart';
import 'invoice_review_handoff_contract.dart';

class InvoiceCaptureReviewFlowResult {
  const InvoiceCaptureReviewFlowResult({
    required this.recognitionResult,
    required this.handoffState,
    required this.formModel,
  });

  final InvoiceAutomaticRecognitionResult recognitionResult;
  final InvoiceReviewHandoffState handoffState;
  final InvoiceReviewFormViewModel formModel;

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
    };
  }
}

class InvoiceCaptureReviewFlowCoordinator {
  const InvoiceCaptureReviewFlowCoordinator({
    required this.recognitionCoordinator,
    this.handoffPresenter = const InvoiceReviewHandoffPresenter(),
    this.formPresenter = const InvoiceReviewFormPresenter(),
  });

  final InvoiceAutomaticRecognitionCoordinator recognitionCoordinator;
  final InvoiceReviewHandoffPresenter handoffPresenter;
  final InvoiceReviewFormPresenter formPresenter;

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
    final formModel = formPresenter.fromHandoff(handoffState);

    return InvoiceCaptureReviewFlowResult(
      recognitionResult: recognitionResult,
      handoffState: handoffState,
      formModel: formModel,
    );
  }
}
