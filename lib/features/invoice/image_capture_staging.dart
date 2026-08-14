import 'daily_capture_entry_shell.dart';

enum ImageCaptureStagingStatus { pendingReview, cancelled }

enum ImageCaptureStagingSource { gallery, camera }

class GalleryPickedImage {
  const GalleryPickedImage({required this.reference, required this.name});

  final String reference;
  final String name;
}

class CameraCapturedImage {
  const CameraCapturedImage({required this.reference, required this.name});

  final String reference;
  final String name;
}

abstract class GalleryImageSource {
  Future<GalleryPickedImage?> pickImage();
}

abstract class CameraImageSource {
  Future<CameraCapturedImage?> captureImage();
}

class ImageCaptureStagingItem {
  const ImageCaptureStagingItem({
    required this.id,
    required this.intent,
    required this.source,
    required this.localReference,
    required this.fileName,
    required this.status,
    required this.createdAt,
    this.discardedAt,
    this.discardReason,
  });

  final DailyCaptureIntent intent;
  final ImageCaptureStagingSource source;
  final String localReference;
  final String fileName;
  final ImageCaptureStagingStatus status;
  final DateTime createdAt;
  final DateTime? discardedAt;
  final String? discardReason;
  final String id;

  bool get isLocalOnly => true;
  bool get needsReview => status == ImageCaptureStagingStatus.pendingReview;
  bool get isDiscarded => status == ImageCaptureStagingStatus.cancelled;
  bool get hasTemporaryImageReference => localReference.trim().isNotEmpty;
  bool get canRunLocalRecognition => needsReview && hasTemporaryImageReference;
  bool get canCreateTransactionAutomatically => false;
  bool get canCreateInvoiceAutomatically => false;

  String get replayProtectionKey {
    final normalizedName = fileName.trim().toLowerCase();
    final createdAtEpoch = createdAt.toUtc().microsecondsSinceEpoch;
    return '${intent.name}:${source.name}:$normalizedName:$createdAtEpoch';
  }

  bool hasSameTemporaryReference(ImageCaptureStagingItem other) {
    final currentReference = localReference.trim();
    final otherReference = other.localReference.trim();
    return currentReference.isNotEmpty && currentReference == otherReference;
  }

  ImageCaptureStagingItem discard({
    DateTime? at,
    String reason = 'user_discarded',
  }) {
    return ImageCaptureStagingItem(
      id: id,
      intent: intent,
      source: source,
      localReference: '',
      fileName: fileName,
      status: ImageCaptureStagingStatus.cancelled,
      createdAt: createdAt,
      discardedAt: at ?? DateTime.now().toUtc(),
      discardReason: reason,
    );
  }

  Map<String, Object?> toSafeLifecycleSummary() {
    return <String, Object?>{
      'id': id,
      'intent': intent.name,
      'source': source.name,
      'status': status.name,
      'isLocalOnly': isLocalOnly,
      'needsReview': needsReview,
      'hasTemporaryImageReference': hasTemporaryImageReference,
      'canRunLocalRecognition': canRunLocalRecognition,
      'canCreateTransactionAutomatically': canCreateTransactionAutomatically,
      'canCreateInvoiceAutomatically': canCreateInvoiceAutomatically,
      'hasDiscardReason': discardReason?.trim().isNotEmpty == true,
    };
  }
}

class ImageCaptureStagingService {
  const ImageCaptureStagingService({
    required this.gallerySource,
    this.cameraSource,
    this.clock,
    this.idFactory,
  });

  final GalleryImageSource gallerySource;
  final CameraImageSource? cameraSource;
  final DateTime Function()? clock;
  final String Function()? idFactory;

  Future<ImageCaptureStagingItem?> createFromGallery({
    required DailyCaptureIntent intent,
  }) async {
    final picked = await gallerySource.pickImage();
    if (picked == null) return null;
    return _createItem(
      intent: intent,
      source: ImageCaptureStagingSource.gallery,
      localReference: picked.reference,
      fileName: picked.name,
      idPrefix: 'gallery',
    );
  }

  Future<ImageCaptureStagingItem?> createFromCamera({
    required DailyCaptureIntent intent,
  }) async {
    final source = cameraSource;
    if (source == null) throw StateError('Camera image source is not configured.');
    final captured = await source.captureImage();
    if (captured == null) return null;
    return _createItem(
      intent: intent,
      source: ImageCaptureStagingSource.camera,
      localReference: captured.reference,
      fileName: captured.name,
      idPrefix: 'camera',
    );
  }

  ImageCaptureStagingItem _createItem({
    required DailyCaptureIntent intent,
    required ImageCaptureStagingSource source,
    required String localReference,
    required String fileName,
    required String idPrefix,
  }) {
    final generatedId = '$idPrefix-${DateTime.now().microsecondsSinceEpoch}';
    return ImageCaptureStagingItem(
      id: idFactory?.call() ?? generatedId,
      intent: intent,
      source: source,
      localReference: localReference,
      fileName: fileName,
      status: ImageCaptureStagingStatus.pendingReview,
      createdAt: clock?.call() ?? DateTime.now(),
    );
  }
}

class ImageCaptureStagingCopy {
  const ImageCaptureStagingCopy._();

  static const String galleryReady = '從相簿選擇後，只會建立本機待審核影像項目。';
  static const String cameraReady = '開啟相機後，只會建立本機待審核影像項目。';
  static const String reviewFirst = '影像辨識結果必須人工確認後，才可建立交易或發票紀錄。';
  static const String discardRemovesTemporaryState =
      '放棄辨識會移除本機暫存影像參照與辨識 payload 狀態。';
}
