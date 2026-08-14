import 'package:flutter/material.dart';

import 'daily_capture_entry_shell.dart';

enum ImageSourcePermissionStatus {
  unknown,
  available,
  denied,
  restricted,
  permanentlyDenied,
}

class ImageSourcePermissionState {
  const ImageSourcePermissionState({
    this.cameraStatus = ImageSourcePermissionStatus.unknown,
    this.galleryStatus = ImageSourcePermissionStatus.unknown,
  });

  final ImageSourcePermissionStatus cameraStatus;
  final ImageSourcePermissionStatus galleryStatus;

  ImageSourcePermissionStatus statusFor(DailyCaptureSource source) {
    switch (source) {
      case DailyCaptureSource.camera:
        return cameraStatus;
      case DailyCaptureSource.gallery:
        return galleryStatus;
    }
  }

  bool canUse(DailyCaptureSource source) => statusFor(source) == ImageSourcePermissionStatus.available;
  bool needsUserReview(DailyCaptureSource source) => statusFor(source) != ImageSourcePermissionStatus.available;
}

class ImageSourcePermissionStatusCard extends StatelessWidget {
  const ImageSourcePermissionStatusCard({
    super.key,
    this.state = const ImageSourcePermissionState(),
  });

  static const Key cardKey = Key('image_source_permission_status_card');
  static const Key cameraStatusKey = Key('image_source_permission_camera_status');
  static const Key galleryStatusKey = Key('image_source_permission_gallery_status');

  final ImageSourcePermissionState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: cardKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ImageSourcePermissionCopy.title,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const _PermissionChip(label: '不主動要求'),
              ],
            ),
            const SizedBox(height: 8),
            const Text(ImageSourcePermissionCopy.description),
            const SizedBox(height: 12),
            _PermissionTile(source: DailyCaptureSource.camera, status: state.cameraStatus),
            _PermissionTile(source: DailyCaptureSource.gallery, status: state.galleryStatus),
          ],
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({required this.source, required this.status});

  final DailyCaptureSource source;
  final ImageSourcePermissionStatus status;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: _keyFor(source),
      contentPadding: EdgeInsets.zero,
      leading: Icon(source == DailyCaptureSource.camera ? Icons.camera_alt_outlined : Icons.photo_library_outlined),
      title: Text(_titleFor(source)),
      subtitle: Text('${_statusLabel(status)}｜${_guidanceFor(status)}'),
      trailing: _PermissionChip(label: _statusLabel(status)),
    );
  }

  static Key _keyFor(DailyCaptureSource source) {
    switch (source) {
      case DailyCaptureSource.camera:
        return ImageSourcePermissionStatusCard.cameraStatusKey;
      case DailyCaptureSource.gallery:
        return ImageSourcePermissionStatusCard.galleryStatusKey;
    }
  }

  static String _titleFor(DailyCaptureSource source) {
    switch (source) {
      case DailyCaptureSource.camera:
        return '相機權限';
      case DailyCaptureSource.gallery:
        return '相簿權限';
    }
  }
}

class _PermissionChip extends StatelessWidget {
  const _PermissionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.secondary;
    return Chip(
      label: Text(label),
      side: BorderSide(color: color),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w800),
    );
  }
}

String _statusLabel(ImageSourcePermissionStatus status) {
  switch (status) {
    case ImageSourcePermissionStatus.unknown:
      return '尚未檢查';
    case ImageSourcePermissionStatus.available:
      return '可使用';
    case ImageSourcePermissionStatus.denied:
      return '已拒絕';
    case ImageSourcePermissionStatus.restricted:
      return '受限制';
    case ImageSourcePermissionStatus.permanentlyDenied:
      return '永久拒絕';
  }
}

String _guidanceFor(ImageSourcePermissionStatus status) {
  switch (status) {
    case ImageSourcePermissionStatus.unknown:
      return '本階段不會主動跳出權限要求。';
    case ImageSourcePermissionStatus.available:
      return '後續可安全接入來源選擇流程。';
    case ImageSourcePermissionStatus.denied:
      return '需使用者理解用途後再手動開啟。';
    case ImageSourcePermissionStatus.restricted:
      return '系統或裝置政策限制，需保留手動建立路徑。';
    case ImageSourcePermissionStatus.permanentlyDenied:
      return '需引導使用者到系統設定調整。';
  }
}

class ImageSourcePermissionCopy {
  const ImageSourcePermissionCopy._();

  static const String title = '影像來源權限狀態';
  static const String description = '相機與相簿會先顯示權限狀態；本階段不會主動要求權限、不會開啟相機或相簿。';
}
