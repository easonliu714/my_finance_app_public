import 'daily_capture_entry_shell.dart';
import 'image_capture_staging.dart';

enum ImageReviewAdapterStatus { readyForReview, blockedByConsent, failed }

enum ImageReviewCandidateKind { invoice, product }

class ImageReviewAdapterRequest {
  const ImageReviewAdapterRequest({
    required this.stagingItem,
    required this.externalAnalysisConsent,
  });

  final ImageCaptureStagingItem stagingItem;
  final bool externalAnalysisConsent;

  DailyCaptureIntent get intent => stagingItem.intent;
  String get localReference => stagingItem.localReference;
}

class ImageReviewCandidate {
  const ImageReviewCandidate({
    required this.kind,
    required this.label,
    this.referenceAmount,
    this.note,
  });

  final ImageReviewCandidateKind kind;
  final String label;
  final double? referenceAmount;
  final String? note;
}

class ImageReviewAdapterResult {
  const ImageReviewAdapterResult({
    required this.status,
    required this.candidates,
    required this.message,
  });

  final ImageReviewAdapterStatus status;
  final List<ImageReviewCandidate> candidates;
  final String message;

  bool get needsReview => true;
  bool get canCreateTransactionAutomatically => false;
  bool get hasAdvisoryCandidates => candidates.isNotEmpty;
}

abstract class ImageReviewAdapter {
  Future<ImageReviewAdapterResult> analyze(ImageReviewAdapterRequest request);
}

class ImageReviewAdapterService {
  const ImageReviewAdapterService({required this.adapter});

  final ImageReviewAdapter adapter;

  Future<ImageReviewAdapterResult> analyze(ImageReviewAdapterRequest request) async {
    if (!request.externalAnalysisConsent) {
      return const ImageReviewAdapterResult(
        status: ImageReviewAdapterStatus.blockedByConsent,
        candidates: <ImageReviewCandidate>[],
        message: '需先取得外部影像分析同意，才可建立辨識候選。',
      );
    }
    return adapter.analyze(request);
  }
}

class MockImageReviewAdapter implements ImageReviewAdapter {
  const MockImageReviewAdapter();

  @override
  Future<ImageReviewAdapterResult> analyze(ImageReviewAdapterRequest request) async {
    switch (request.intent) {
      case DailyCaptureIntent.invoice:
        return const ImageReviewAdapterResult(
          status: ImageReviewAdapterStatus.readyForReview,
          candidates: <ImageReviewCandidate>[
            ImageReviewCandidate(kind: ImageReviewCandidateKind.invoice, label: '發票候選', note: '待人工核對號碼、日期與金額'),
          ],
          message: '已建立發票辨識候選，需人工確認。',
        );
      case DailyCaptureIntent.product:
        return const ImageReviewAdapterResult(
          status: ImageReviewAdapterStatus.readyForReview,
          candidates: <ImageReviewCandidate>[
            ImageReviewCandidate(kind: ImageReviewCandidateKind.product, label: '商品候選', referenceAmount: 0, note: '待人工核對品名與價格'),
          ],
          message: '已建立商品辨識候選，需人工確認。',
        );
    }
  }
}

class ImageReviewAdapterCopy {
  const ImageReviewAdapterCopy._();

  static const String consentRequired = '外部影像分析必須先由使用者明確同意。';
  static const String advisoryOnly = '辨識結果只作為待審核候選，不會自動建立交易或發票。';
}
