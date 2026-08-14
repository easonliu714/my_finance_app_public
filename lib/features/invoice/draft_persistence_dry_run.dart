import 'draft_persistence_plan.dart';
import 'image_review_adapter.dart';
import 'image_review_draft.dart';

class DraftPersistenceDryRunRequest {
  const DraftPersistenceDryRunRequest({
    required this.draft,
    required this.reviewNote,
    required this.createdAt,
    required this.updatedAt,
  });

  final ImageReviewDraftCandidate draft;
  final String? reviewNote;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class DraftPersistenceDryRunResult {
  const DraftPersistenceDryRunResult({
    required this.accepted,
    required this.payload,
    required this.missingFields,
    required this.message,
  });

  final bool accepted;
  final Map<String, Object?> payload;
  final List<String> missingFields;
  final String message;

  bool get isLocalOnly => true;
  bool get requiresManualReview => true;
  bool get canWriteRuntimeStorage => false;
  bool get canCreateFinalRecordAutomatically => false;
}

class DraftPersistenceDryRunService {
  const DraftPersistenceDryRunService();

  DraftPersistenceDryRunResult buildPayload(DraftPersistenceDryRunRequest request) {
    final payload = <String, Object?>{
      'id': request.draft.id,
      'draft_kind': _draftKindValue(request.draft.kind),
      'review_state': _reviewStateValue(request.draft.status),
      'source_candidate_kind': _candidateKindValue(request.draft.sourceCandidate.kind),
      'source_candidate_label': request.draft.sourceCandidate.label,
      'source_candidate_amount': request.draft.sourceCandidate.referenceAmount,
      'source_candidate_note': request.draft.sourceCandidate.note,
      'review_note': request.reviewNote,
      'created_at': request.createdAt.toIso8601String(),
      'updated_at': request.updatedAt.toIso8601String(),
    };
    final missingFields = DraftPersistencePlan.fieldNames.where((field) => _isRequired(field) && _isBlank(payload[field])).toList(growable: false);
    return DraftPersistenceDryRunResult(
      accepted: missingFields.isEmpty,
      payload: payload,
      missingFields: missingFields,
      message: missingFields.isEmpty ? 'Dry-run payload is ready for manual review.' : 'Dry-run payload has missing required fields.',
    );
  }

  static bool _isRequired(String field) {
    return const <String>{
      'id',
      'draft_kind',
      'review_state',
      'source_candidate_kind',
      'source_candidate_label',
      'created_at',
      'updated_at',
    }.contains(field);
  }

  static bool _isBlank(Object? value) {
    return value == null || (value is String && value.trim().isEmpty);
  }

  static String _draftKindValue(ImageReviewDraftKind kind) {
    switch (kind) {
      case ImageReviewDraftKind.invoice:
        return 'invoice';
      case ImageReviewDraftKind.transaction:
        return 'transaction';
    }
  }

  static String _reviewStateValue(ImageReviewDraftStatus status) {
    switch (status) {
      case ImageReviewDraftStatus.pendingEdit:
        return 'pending_edit';
      case ImageReviewDraftStatus.discarded:
        return 'discarded';
    }
  }

  static String _candidateKindValue(ImageReviewCandidateKind kind) {
    switch (kind) {
      case ImageReviewCandidateKind.invoice:
        return 'invoice';
      case ImageReviewCandidateKind.product:
        return 'product';
    }
  }
}

class DraftPersistenceDryRunCopy {
  const DraftPersistenceDryRunCopy._();

  static const String dryRunOnly = '此階段只建立 dry-run payload，不寫入執行期儲存。';
  static const String reviewOnly = 'dry-run 結果仍需人工審核，不會自動建立正式紀錄。';
}
