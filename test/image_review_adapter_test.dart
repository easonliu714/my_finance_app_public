import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/daily_capture_entry_shell.dart';
import 'package:my_finance_app/features/invoice/image_capture_staging.dart';
import 'package:my_finance_app/features/invoice/image_review_adapter.dart';

void main() {
  test('adapter service blocks analysis without consent', () async {
    const service = ImageReviewAdapterService(adapter: MockImageReviewAdapter());
    final request = ImageReviewAdapterRequest(
      stagingItem: _stagingItem(intent: DailyCaptureIntent.invoice),
      externalAnalysisConsent: false,
    );

    final result = await service.analyze(request);

    expect(result.status, ImageReviewAdapterStatus.blockedByConsent);
    expect(result.candidates, isEmpty);
    expect(result.needsReview, isTrue);
    expect(result.canCreateTransactionAutomatically, isFalse);
  });

  test('mock adapter returns invoice advisory candidate with review gate', () async {
    const service = ImageReviewAdapterService(adapter: MockImageReviewAdapter());
    final request = ImageReviewAdapterRequest(
      stagingItem: _stagingItem(intent: DailyCaptureIntent.invoice),
      externalAnalysisConsent: true,
    );

    final result = await service.analyze(request);

    expect(result.status, ImageReviewAdapterStatus.readyForReview);
    expect(result.candidates.single.kind, ImageReviewCandidateKind.invoice);
    expect(result.hasAdvisoryCandidates, isTrue);
    expect(result.needsReview, isTrue);
    expect(result.canCreateTransactionAutomatically, isFalse);
  });

  test('mock adapter returns product advisory candidate with review gate', () async {
    const service = ImageReviewAdapterService(adapter: MockImageReviewAdapter());
    final request = ImageReviewAdapterRequest(
      stagingItem: _stagingItem(intent: DailyCaptureIntent.product),
      externalAnalysisConsent: true,
    );

    final result = await service.analyze(request);

    expect(result.status, ImageReviewAdapterStatus.readyForReview);
    expect(result.candidates.single.kind, ImageReviewCandidateKind.product);
    expect(result.hasAdvisoryCandidates, isTrue);
    expect(result.needsReview, isTrue);
    expect(result.canCreateTransactionAutomatically, isFalse);
  });

  test('adapter copy states consent and advisory-only boundaries', () {
    expect(ImageReviewAdapterCopy.consentRequired, contains('明確同意'));
    expect(ImageReviewAdapterCopy.advisoryOnly, contains('不會自動建立交易'));
  });
}

ImageCaptureStagingItem _stagingItem({required DailyCaptureIntent intent}) {
  return ImageCaptureStagingItem(
    id: 'staging-1',
    intent: intent,
    source: ImageCaptureStagingSource.gallery,
    localReference: 'local-image.jpg',
    fileName: 'local-image.jpg',
    status: ImageCaptureStagingStatus.pendingReview,
    createdAt: DateTime.utc(2026, 6, 12),
  );
}
