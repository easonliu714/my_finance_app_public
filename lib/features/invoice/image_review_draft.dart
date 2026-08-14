import 'image_review_adapter.dart';

enum ImageReviewDraftKind { invoice, transaction }

enum ImageReviewDraftStatus { pendingEdit, discarded }

class ImageReviewDraftCandidate {
  const ImageReviewDraftCandidate({
    required this.id,
    required this.kind,
    required this.sourceCandidate,
    required this.status,
  });

  final String id;
  final ImageReviewDraftKind kind;
  final ImageReviewCandidate sourceCandidate;
  final ImageReviewDraftStatus status;

  bool get isLocalOnly => true;
  bool get needsEditReview => status == ImageReviewDraftStatus.pendingEdit;
  bool get canCreateTransactionAutomatically => false;
  bool get canCreateInvoiceAutomatically => false;
}

class ImageReviewDraftService {
  const ImageReviewDraftService({this.idFactory});

  final String Function()? idFactory;

  ImageReviewDraftCandidate? confirmCandidate({
    required ImageReviewCandidate candidate,
    required bool confirmed,
  }) {
    if (!confirmed) return null;
    return ImageReviewDraftCandidate(
      id: idFactory?.call() ?? 'review-draft-${DateTime.now().microsecondsSinceEpoch}',
      kind: _draftKind(candidate.kind),
      sourceCandidate: candidate,
      status: ImageReviewDraftStatus.pendingEdit,
    );
  }

  static ImageReviewDraftKind _draftKind(ImageReviewCandidateKind kind) {
    switch (kind) {
      case ImageReviewCandidateKind.invoice:
        return ImageReviewDraftKind.invoice;
      case ImageReviewCandidateKind.product:
        return ImageReviewDraftKind.transaction;
    }
  }
}

class ImageReviewDraftCopy {
  const ImageReviewDraftCopy._();

  static const String confirmationRequired = '候選結果必須經使用者確認後，才會建立本機草稿。';
  static const String localDraftOnly = '本機草稿仍需編輯與確認，不會自動寫入正式交易或發票。';
}
