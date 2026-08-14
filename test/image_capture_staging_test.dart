import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/daily_capture_entry_shell.dart';
import 'package:my_finance_app/features/invoice/image_capture_staging.dart';

void main() {
  test('gallery source creates review-first staging item for invoice intent', () async {
    final service = ImageCaptureStagingService(
      gallerySource: const _FakeGallerySource(
        GalleryPickedImage(reference: 'invoice.jpg', name: 'invoice.jpg'),
      ),
      clock: () => DateTime.utc(2026, 6, 12),
      idFactory: () => 'gallery-1',
    );

    final item = await service.createFromGallery(intent: DailyCaptureIntent.invoice);

    expect(item, isNotNull);
    expect(item!.id, 'gallery-1');
    expect(item.intent, DailyCaptureIntent.invoice);
    expect(item.source, ImageCaptureStagingSource.gallery);
    expect(item.localReference, 'invoice.jpg');
    expect(item.fileName, 'invoice.jpg');
    expect(item.status, ImageCaptureStagingStatus.pendingReview);
    expect(item.isLocalOnly, isTrue);
    expect(item.needsReview, isTrue);
    expect(item.canRunLocalRecognition, isTrue);
    expect(item.canCreateTransactionAutomatically, isFalse);
    expect(item.canCreateInvoiceAutomatically, isFalse);
  });

  test('camera source creates review-first staging item for invoice intent', () async {
    final service = ImageCaptureStagingService(
      gallerySource: const _FakeGallerySource(null),
      cameraSource: const _FakeCameraSource(
        CameraCapturedImage(
          reference: 'camera-invoice.jpg',
          name: 'camera-invoice.jpg',
        ),
      ),
      clock: () => DateTime.utc(2026, 6, 12),
      idFactory: () => 'camera-1',
    );

    final item = await service.createFromCamera(intent: DailyCaptureIntent.invoice);

    expect(item, isNotNull);
    expect(item!.id, 'camera-1');
    expect(item.intent, DailyCaptureIntent.invoice);
    expect(item.source, ImageCaptureStagingSource.camera);
    expect(item.localReference, 'camera-invoice.jpg');
    expect(item.fileName, 'camera-invoice.jpg');
    expect(item.status, ImageCaptureStagingStatus.pendingReview);
    expect(item.isLocalOnly, isTrue);
    expect(item.needsReview, isTrue);
    expect(item.canRunLocalRecognition, isTrue);
    expect(item.canCreateTransactionAutomatically, isFalse);
  });

  test('camera source creates review-first staging item for product intent', () async {
    final service = ImageCaptureStagingService(
      gallerySource: const _FakeGallerySource(null),
      cameraSource: const _FakeCameraSource(
        CameraCapturedImage(
          reference: 'camera-product.jpg',
          name: 'camera-product.jpg',
        ),
      ),
      idFactory: () => 'camera-product',
    );

    final item = await service.createFromCamera(intent: DailyCaptureIntent.product);

    expect(item, isNotNull);
    expect(item!.id, 'camera-product');
    expect(item.intent, DailyCaptureIntent.product);
    expect(item.source, ImageCaptureStagingSource.camera);
    expect(item.needsReview, isTrue);
    expect(item.canRunLocalRecognition, isTrue);
    expect(item.canCreateTransactionAutomatically, isFalse);
  });

  test('discard clears temporary reference and blocks local recognition', () async {
    final service = ImageCaptureStagingService(
      gallerySource: const _FakeGallerySource(
        GalleryPickedImage(reference: '/tmp/invoice.jpg', name: 'invoice.jpg'),
      ),
      clock: () => DateTime.utc(2026, 6, 12),
      idFactory: () => 'gallery-discard',
    );

    final item = await service.createFromGallery(intent: DailyCaptureIntent.invoice);
    final discarded = item!.discard(
      at: DateTime.utc(2026, 6, 13),
      reason: 'user_cancelled_review',
    );

    expect(discarded.id, item.id);
    expect(discarded.status, ImageCaptureStagingStatus.cancelled);
    expect(discarded.isDiscarded, isTrue);
    expect(discarded.localReference, isEmpty);
    expect(discarded.hasTemporaryImageReference, isFalse);
    expect(discarded.needsReview, isFalse);
    expect(discarded.canRunLocalRecognition, isFalse);
    expect(discarded.canCreateTransactionAutomatically, isFalse);
    expect(discarded.canCreateInvoiceAutomatically, isFalse);
    expect(discarded.discardReason, 'user_cancelled_review');
    expect(discarded.discardedAt, DateTime.utc(2026, 6, 13));
  });

  test('safe lifecycle summary exposes state only without raw path or filename', () async {
    final service = ImageCaptureStagingService(
      gallerySource: const _FakeGallerySource(
        GalleryPickedImage(
          reference: '/private/tmp/invoice.jpg',
          name: 'invoice.jpg',
        ),
      ),
      clock: () => DateTime.utc(2026, 6, 12),
      idFactory: () => 'safe-summary',
    );

    final summary = (await service.createFromGallery(
      intent: DailyCaptureIntent.invoice,
    ))!
        .toSafeLifecycleSummary();

    expect(summary['id'], 'safe-summary');
    expect(summary['intent'], 'invoice');
    expect(summary['source'], 'gallery');
    expect(summary['status'], 'pendingReview');
    expect(summary['hasTemporaryImageReference'], isTrue);
    expect(summary['canRunLocalRecognition'], isTrue);
    expect(summary.containsKey('localReference'), isFalse);
    expect(summary.containsKey('fileName'), isFalse);
    expect(summary.values, isNot(contains('/private/tmp/invoice.jpg')));
    expect(summary.values, isNot(contains('invoice.jpg')));
  });

  test('replay and duplicate guards are deterministic without exposing payload', () {
    final createdAt = DateTime.utc(2026, 6, 12, 1, 2, 3);
    final first = ImageCaptureStagingItem(
      id: 'first',
      intent: DailyCaptureIntent.invoice,
      source: ImageCaptureStagingSource.gallery,
      localReference: '/tmp/a.jpg',
      fileName: 'Invoice.JPG',
      status: ImageCaptureStagingStatus.pendingReview,
      createdAt: createdAt,
    );
    final second = ImageCaptureStagingItem(
      id: 'second',
      intent: DailyCaptureIntent.invoice,
      source: ImageCaptureStagingSource.gallery,
      localReference: '/tmp/a.jpg',
      fileName: 'invoice.jpg',
      status: ImageCaptureStagingStatus.pendingReview,
      createdAt: createdAt,
    );

    expect(first.replayProtectionKey, second.replayProtectionKey);
    expect(first.hasSameTemporaryReference(second), isTrue);
    expect(first.replayProtectionKey, isNot(contains('/tmp/a.jpg')));
  });

  test('cancelled gallery source returns null', () async {
    const service = ImageCaptureStagingService(
      gallerySource: _FakeGallerySource(null),
    );

    final item = await service.createFromGallery(intent: DailyCaptureIntent.invoice);

    expect(item, isNull);
  });

  test('cancelled camera source returns null', () async {
    const service = ImageCaptureStagingService(
      gallerySource: _FakeGallerySource(null),
      cameraSource: _FakeCameraSource(null),
    );

    final item = await service.createFromCamera(intent: DailyCaptureIntent.invoice);

    expect(item, isNull);
  });

  test('camera source must be configured before capture', () async {
    const service = ImageCaptureStagingService(
      gallerySource: _FakeGallerySource(null),
    );

    expect(
      () => service.createFromCamera(intent: DailyCaptureIntent.invoice),
      throwsStateError,
    );
  });
}

class _FakeGallerySource implements GalleryImageSource {
  const _FakeGallerySource(this.image);

  final GalleryPickedImage? image;

  @override
  Future<GalleryPickedImage?> pickImage() async => image;
}

class _FakeCameraSource implements CameraImageSource {
  const _FakeCameraSource(this.image);

  final CameraCapturedImage? image;

  @override
  Future<CameraCapturedImage?> captureImage() async => image;
}
