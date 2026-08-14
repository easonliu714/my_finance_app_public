import 'daily_capture_entry_shell.dart';
import 'image_capture_staging.dart';

enum ProductionImageCaptureStatus {
  staged,
  cancelled,
  duplicateRequest,
  duplicateImage,
  replayRejected,
  sourceUnavailable,
  unreadableReference,
  failed,
  discarded,
  consumed,
}

class ProductionImageCaptureResult {
  const ProductionImageCaptureResult({
    required this.status,
    required this.message,
    this.item,
  });

  final ProductionImageCaptureStatus status;
  final String message;
  final ImageCaptureStagingItem? item;

  bool get hasStagedItem =>
      status == ProductionImageCaptureStatus.staged && item != null;
  bool get canCreateFormalRecord => false;
  bool get remainsLocalOnly => true;
}

abstract class StagedImageCleanupPort {
  Future<void> removeLocalReference(String localReference);
}

class NoopStagedImageCleanupPort implements StagedImageCleanupPort {
  const NoopStagedImageCleanupPort();

  @override
  Future<void> removeLocalReference(String localReference) async {}
}

class ProductionImageCaptureCoordinator {
  ProductionImageCaptureCoordinator({
    required this.stagingService,
    this.cleanupPort = const NoopStagedImageCleanupPort(),
  });

  final ImageCaptureStagingService stagingService;
  final StagedImageCleanupPort cleanupPort;
  final Set<String> _activeRequests = <String>{};
  final Set<String> _consumedReferences = <String>{};
  ImageCaptureStagingItem? _currentItem;
  List<String> _currentRecognitionPayloads = const <String>[];

  ImageCaptureStagingItem? get currentItem => _currentItem;
  bool get hasPendingReview => _currentItem?.needsReview == true;
  List<String> get currentRecognitionPayloads =>
      List<String>.unmodifiable(_currentRecognitionPayloads);

  bool wasConsumed(String localReference) {
    return _consumedReferences.contains(localReference.trim());
  }

  Future<ProductionImageCaptureResult> captureFromGallery({
    required DailyCaptureIntent intent,
  }) {
    return _run(
      intent: intent,
      source: ImageCaptureStagingSource.gallery,
      action: () => stagingService.createFromGallery(intent: intent),
    );
  }

  Future<ProductionImageCaptureResult> captureFromCamera({
    required DailyCaptureIntent intent,
  }) {
    return _run(
      intent: intent,
      source: ImageCaptureStagingSource.camera,
      action: () => stagingService.createFromCamera(intent: intent),
    );
  }

  /// Stages the exact high-resolution JPEG frozen by the production Live page.
  /// The item intentionally reuses the normal camera source contract so all
  /// downstream QR/OCR and Gemini paths operate on the same local reference.
  Future<ProductionImageCaptureResult> stageFrozenLiveCameraImage({
    required DailyCaptureIntent intent,
    required String localReference,
    required String fileName,
  }) {
    final now = DateTime.now();
    return _run(
      intent: intent,
      source: ImageCaptureStagingSource.camera,
      action: () async => ImageCaptureStagingItem(
        id: 'live-${now.microsecondsSinceEpoch}',
        intent: intent,
        source: ImageCaptureStagingSource.camera,
        localReference: localReference.trim(),
        fileName: fileName.trim().isEmpty
            ? 'live_invoice_${now.microsecondsSinceEpoch}.jpg'
            : fileName.trim(),
        status: ImageCaptureStagingStatus.pendingReview,
        createdAt: now,
      ),
    );
  }

  bool attachRecognitionPayloads(List<String> payloads) {
    if (_currentItem == null) return false;
    final normalized = <String>[];
    final seen = <String>{};
    for (final payload in payloads) {
      final value = payload.trim();
      if (value.isEmpty || !seen.add(value)) continue;
      normalized.add(value);
    }
    _currentRecognitionPayloads = List<String>.unmodifiable(normalized);
    return true;
  }

  ProductionImageCaptureResult markCurrentConsumed() {
    final item = _currentItem;
    if (item == null) {
      return const ProductionImageCaptureResult(
        status: ProductionImageCaptureStatus.failed,
        message: '目前沒有可標記為已處理的本機影像。',
      );
    }
    _consumedReferences.add(item.localReference.trim());
    _currentItem = null;
    _currentRecognitionPayloads = const <String>[];
    return const ProductionImageCaptureResult(
      status: ProductionImageCaptureStatus.consumed,
      message: '已完成本機影像覆核狀態，後續相同影像會被視為重播。',
    );
  }

  Future<ProductionImageCaptureResult> discardCurrent() async {
    final item = _currentItem;
    if (item == null) {
      _currentRecognitionPayloads = const <String>[];
      return const ProductionImageCaptureResult(
        status: ProductionImageCaptureStatus.discarded,
        message: '目前沒有待丟棄的本機影像。',
      );
    }
    try {
      await cleanupPort.removeLocalReference(item.localReference);
    } catch (_) {
      _currentItem = null;
      _currentRecognitionPayloads = const <String>[];
      return const ProductionImageCaptureResult(
        status: ProductionImageCaptureStatus.failed,
        message: '本機影像清除失敗，但暫存辨識狀態已移除。',
      );
    }
    _currentItem = null;
    _currentRecognitionPayloads = const <String>[];
    return const ProductionImageCaptureResult(
      status: ProductionImageCaptureStatus.discarded,
      message: '已丟棄本機待審核影像與辨識暫存，不會建立任何正式紀錄。',
    );
  }

  Future<ProductionImageCaptureResult> _run({
    required DailyCaptureIntent intent,
    required ImageCaptureStagingSource source,
    required Future<ImageCaptureStagingItem?> Function() action,
  }) async {
    final key = '${intent.name}:${source.name}';
    if (!_activeRequests.add(key)) {
      return const ProductionImageCaptureResult(
        status: ProductionImageCaptureStatus.duplicateRequest,
        message: '相同來源的影像選擇仍在進行中，請勿重複開啟。',
      );
    }
    try {
      final item = await action();
      if (item == null) {
        return const ProductionImageCaptureResult(
          status: ProductionImageCaptureStatus.cancelled,
          message: '已取消影像選擇，沒有建立待審核項目。',
        );
      }
      final reference = item.localReference.trim();
      if (reference.isEmpty) {
        return const ProductionImageCaptureResult(
          status: ProductionImageCaptureStatus.unreadableReference,
          message: '選取的影像沒有可讀取的本機位置，請重新選擇。',
        );
      }
      if (_currentItem?.localReference.trim() == reference) {
        return const ProductionImageCaptureResult(
          status: ProductionImageCaptureStatus.duplicateImage,
          message: '此影像已在待審核清單中，未重複建立暫存項目。',
        );
      }
      if (_consumedReferences.contains(reference)) {
        return const ProductionImageCaptureResult(
          status: ProductionImageCaptureStatus.replayRejected,
          message: '此影像已完成先前覆核，已阻擋重複處理。',
        );
      }
      _currentItem = item;
      _currentRecognitionPayloads = const <String>[];
      return ProductionImageCaptureResult(
        status: ProductionImageCaptureStatus.staged,
        item: item,
        message: '已建立本機待審核影像，下一步會優先嘗試本機 QR 辨識。',
      );
    } on StateError {
      return const ProductionImageCaptureResult(
        status: ProductionImageCaptureStatus.sourceUnavailable,
        message: '目前無法使用此影像來源，請改用其他方式。',
      );
    } catch (_) {
      return const ProductionImageCaptureResult(
        status: ProductionImageCaptureStatus.failed,
        message: '影像來源發生錯誤，沒有建立待審核項目。',
      );
    } finally {
      _activeRequests.remove(key);
    }
  }
}
