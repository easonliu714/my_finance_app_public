import 'invoice_review_form_view_model.dart';

extension InvoiceReviewSubmissionGateX on InvoiceReviewFormViewModel {
  bool get requiredFieldsComplete => fields
      .where((field) => field.requiredForReview)
      .every((field) => !field.isBlank);

  int get missingRequiredFieldCount => fields
      .where((field) => field.requiredForReview && field.isBlank)
      .length;

  bool get canSubmitReviewSafely =>
      canSubmitForReview && requiredFieldsComplete;

  Map<String, Object?> toSafeSubmissionSummary() {
    return <String, Object?>{
      ...toSafeSummary(),
      'missingRequiredFieldCount': missingRequiredFieldCount,
      'requiredFieldsComplete': requiredFieldsComplete,
      'canSubmitReviewSafely': canSubmitReviewSafely,
    };
  }
}
