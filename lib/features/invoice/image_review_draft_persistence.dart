import 'image_review_draft.dart';

enum ImageReviewDraftPersistenceStatus { acceptedForLocalReview, blockedByConfirmation }

class ImageReviewDraftPersistenceRequest {
  const ImageReviewDraftPersistenceRequest({
    required this.draft,
    required this.confirmed,
  });

  final ImageReviewDraftCandidate draft;
  final bool confirmed;
}

class ImageReviewDraftPersistenceResult {
  const ImageReviewDraftPersistenceResult({
    required this.status,
    required this.draft,
    required this.message,
  });

  final ImageReviewDraftPersistenceStatus status;
  final ImageReviewDraftCandidate? draft;
  final String message;

  bool get isLocalOnly => true;
  bool get needsFinalReview => status == ImageReviewDraftPersistenceStatus.acceptedForLocalReview;
  bool get canWriteFinalTransactionAutomatically => false;
  bool get canWriteFinalInvoiceAutomatically => false;
}

abstract class ImageReviewDraftStore {
  Future<void> saveForReview(ImageReviewDraftCandidate draft);
  Future<List<ImageReviewDraftCandidate>> listPendingReviewDrafts();
}

class InMemoryImageReviewDraftStore implements ImageReviewDraftStore {
  final List<ImageReviewDraftCandidate> _drafts = <ImageReviewDraftCandidate>[];

  @override
  Future<void> saveForReview(ImageReviewDraftCandidate draft) async {
    _drafts.add(draft);
  }

  @override
  Future<List<ImageReviewDraftCandidate>> listPendingReviewDrafts() async {
    return List<ImageReviewDraftCandidate>.unmodifiable(_drafts);
  }
}

class ImageReviewDraftPersistenceService {
  const ImageReviewDraftPersistenceService({required this.store});

  final ImageReviewDraftStore store;

  Future<ImageReviewDraftPersistenceResult> persistForReview(ImageReviewDraftPersistenceRequest request) async {
    if (!request.confirmed) {
      return const ImageReviewDraftPersistenceResult(
        status: ImageReviewDraftPersistenceStatus.blockedByConfirmation,
        draft: null,
        message: '需先確認本機草稿，才可加入待審核清單。',
      );
    }
    await store.saveForReview(request.draft);
    return ImageReviewDraftPersistenceResult(
      status: ImageReviewDraftPersistenceStatus.acceptedForLocalReview,
      draft: request.draft,
      message: '已加入本機待審核草稿清單。',
    );
  }
}

class ImageReviewDraftPersistenceCopy {
  const ImageReviewDraftPersistenceCopy._();

  static const String confirmationRequired = '需先確認本機草稿，才可加入待審核清單。';
  static const String reviewBoundary = '待審核草稿不會自動寫入正式交易或發票。';
}
