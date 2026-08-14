import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/daily_capture_entry_shell.dart';
import 'package:my_finance_app/features/invoice/image_capture_staging.dart';
import 'package:my_finance_app/features/invoice/production_image_capture.dart';

void main() {
  test('gallery selection stages one local review item', () async {
    final coordinator = ProductionImageCaptureCoordinator(
      stagingService: ImageCaptureStagingService(
        gallerySource: const _GallerySource(
          GalleryPickedImage(
            reference: '/tmp/invoice.jpg',
            name: 'invoice.jpg',
          ),
        ),
        idFactory: () => 'stage-1',
        clock: () => DateTime.utc(2026, 7, 4, 16),
      ),
    );

    final result = await coordinator.captureFromGallery(
      intent: DailyCaptureIntent.invoice,
    );

    expect(result.status, ProductionImageCaptureStatus.staged);
    expect(result.item?.id, 'stage-1');
    expect(result.item?.source, ImageCaptureStagingSource.gallery);
    expect(result.item?.intent, DailyCaptureIntent.invoice);
    expect(result.item?.isLocalOnly, isTrue);
    expect(result.canCreateFormalRecord, isFalse);
    expect(coordinator.hasPendingReview, isTrue);
  });

  test('cancelled picker creates no staging item', () async {
    final coordinator = ProductionImageCaptureCoordinator(
      stagingService: const ImageCaptureStagingService(
        gallerySource: _GallerySource(null),
      ),
    );

    final result = await coordinator.captureFromGallery(
      intent: DailyCaptureIntent.invoice,
    );

    expect(result.status, ProductionImageCaptureStatus.cancelled);
    expect(result.item, isNull);
    expect(coordinator.currentItem, isNull);
  });

  test('camera unavailable fails closed', () async {
    final coordinator = ProductionImageCaptureCoordinator(
      stagingService: const ImageCaptureStagingService(
        gallerySource: _GallerySource(null),
      ),
    );

    final result = await coordinator.captureFromCamera(
      intent: DailyCaptureIntent.invoice,
    );

    expect(result.status, ProductionImageCaptureStatus.sourceUnavailable);
    expect(result.item, isNull);
  });

  test('unreadable local reference is blocked', () async {
    final coordinator = ProductionImageCaptureCoordinator(
      stagingService: const ImageCaptureStagingService(
        gallerySource: _GallerySource(
          GalleryPickedImage(reference: '   ', name: 'invoice.jpg'),
        ),
      ),
    );

    final result = await coordinator.captureFromGallery(
      intent: DailyCaptureIntent.invoice,
    );

    expect(result.status, ProductionImageCaptureStatus.unreadableReference);
    expect(result.item, isNull);
  });

  test('same active source request is rejected deterministically', () async {
    final completer = Completer<GalleryPickedImage?>();
    final coordinator = ProductionImageCaptureCoordinator(
      stagingService: ImageCaptureStagingService(
        gallerySource: _DeferredGallerySource(completer.future),
      ),
    );

    final first = coordinator.captureFromGallery(
      intent: DailyCaptureIntent.invoice,
    );
    final duplicate = await coordinator.captureFromGallery(
      intent: DailyCaptureIntent.invoice,
    );

    expect(duplicate.status, ProductionImageCaptureStatus.duplicateRequest);
    completer.complete(
      const GalleryPickedImage(
        reference: '/tmp/first.jpg',
        name: 'first.jpg',
      ),
    );
    expect((await first).status, ProductionImageCaptureStatus.staged);
  });

  test('same staged image reference is not staged twice', () async {
    final coordinator = ProductionImageCaptureCoordinator(
      stagingService: const ImageCaptureStagingService(
        gallerySource: _GallerySource(
          GalleryPickedImage(
            reference: '/tmp/duplicate.jpg',
            name: 'duplicate.jpg',
          ),
        ),
      ),
    );

    final first = await coordinator.captureFromGallery(
      intent: DailyCaptureIntent.invoice,
    );
    final duplicate = await coordinator.captureFromGallery(
      intent: DailyCaptureIntent.invoice,
    );

    expect(first.status, ProductionImageCaptureStatus.staged);
    expect(duplicate.status, ProductionImageCaptureStatus.duplicateImage);
    expect(coordinator.currentItem?.localReference, '/tmp/duplicate.jpg');
    expect(duplicate.canCreateFormalRecord, isFalse);
  });

  test('recognition payloads are normalized and remain local', () async {
    final coordinator = ProductionImageCaptureCoordinator(
      stagingService: const ImageCaptureStagingService(
        gallerySource: _GallerySource(
          GalleryPickedImage(
            reference: '/tmp/payload.jpg',
            name: 'payload.jpg',
          ),
        ),
      ),
    );
    await coordinator.captureFromGallery(intent: DailyCaptureIntent.invoice);

    final attached = coordinator.attachRecognitionPayloads(
      const <String>[' left ', 'right', 'left', '  '],
    );

    expect(attached, isTrue);
    expect(coordinator.currentRecognitionPayloads, <String>['left', 'right']);
    expect(coordinator.currentItem?.isLocalOnly, isTrue);
  });

  test('consumed image reference is blocked from replay', () async {
    final coordinator = ProductionImageCaptureCoordinator(
      stagingService: const ImageCaptureStagingService(
        gallerySource: _GallerySource(
          GalleryPickedImage(
            reference: '/tmp/replay.jpg',
            name: 'replay.jpg',
          ),
        ),
      ),
    );
    await coordinator.captureFromGallery(intent: DailyCaptureIntent.invoice);
    coordinator.attachRecognitionPayloads(const <String>['left', 'right']);

    final consumed = coordinator.markCurrentConsumed();
    final replay = await coordinator.captureFromGallery(
      intent: DailyCaptureIntent.invoice,
    );

    expect(consumed.status, ProductionImageCaptureStatus.consumed);
    expect(coordinator.wasConsumed('/tmp/replay.jpg'), isTrue);
    expect(coordinator.currentRecognitionPayloads, isEmpty);
    expect(replay.status, ProductionImageCaptureStatus.replayRejected);
    expect(replay.item, isNull);
    expect(replay.canCreateFormalRecord, isFalse);
  });

  test('discard removes local reference and clears payload state', () async {
    final cleanup = _CleanupPort();
    final coordinator = ProductionImageCaptureCoordinator(
      stagingService: const ImageCaptureStagingService(
        gallerySource: _GallerySource(
          GalleryPickedImage(
            reference: '/tmp/discard.jpg',
            name: 'discard.jpg',
          ),
        ),
      ),
      cleanupPort: cleanup,
    );
    await coordinator.captureFromGallery(intent: DailyCaptureIntent.invoice);
    coordinator.attachRecognitionPayloads(const <String>['left', 'right']);

    final result = await coordinator.discardCurrent();

    expect(result.status, ProductionImageCaptureStatus.discarded);
    expect(cleanup.removed, <String>['/tmp/discard.jpg']);
    expect(coordinator.currentItem, isNull);
    expect(coordinator.currentRecognitionPayloads, isEmpty);
    expect(coordinator.wasConsumed('/tmp/discard.jpg'), isFalse);
  });

  test('payloads cannot be attached without a staged item', () {
    final coordinator = ProductionImageCaptureCoordinator(
      stagingService: const ImageCaptureStagingService(
        gallerySource: _GallerySource(null),
      ),
    );

    expect(
      coordinator.attachRecognitionPayloads(const <String>['left']),
      isFalse,
    );
    expect(coordinator.currentRecognitionPayloads, isEmpty);
  });
}

class _GallerySource implements GalleryImageSource {
  const _GallerySource(this.image);

  final GalleryPickedImage? image;

  @override
  Future<GalleryPickedImage?> pickImage() async => image;
}

class _DeferredGallerySource implements GalleryImageSource {
  const _DeferredGallerySource(this.future);

  final Future<GalleryPickedImage?> future;

  @override
  Future<GalleryPickedImage?> pickImage() => future;
}

class _CleanupPort implements StagedImageCleanupPort {
  final List<String> removed = <String>[];

  @override
  Future<void> removeLocalReference(String localReference) async {
    removed.add(localReference);
  }
}
