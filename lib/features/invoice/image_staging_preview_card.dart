import 'package:flutter/material.dart';

import 'image_staging_preview.dart';

class ImageStagingPreviewCard extends StatelessWidget {
  const ImageStagingPreviewCard({
    super.key,
    this.state = const ImageStagingPreviewState(),
  });

  static const Key cardKey = Key('image_staging_preview_card');
  static const Key sourceChoicesKey = Key('image_staging_source_choices');
  static const Key previewSummaryKey = Key('image_staging_preview_summary');
  static const Key cameraChoiceKey = Key('image_staging_camera_choice');
  static const Key galleryChoiceKey = Key('image_staging_gallery_choice');
  static const Key manualChoiceKey = Key('image_staging_manual_choice');

  final ImageStagingPreviewState state;

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
                const Icon(Icons.camera_alt_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ImageStagingPreviewCopy.title,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                _PreviewStatusChip(label: state.isEmpty ? '待建立' : '待審核 ${state.readyCount}'),
              ],
            ),
            const SizedBox(height: 8),
            const Text(ImageStagingPreviewCopy.subtitle),
            const SizedBox(height: 8),
            const Text(ImageStagingPreviewCopy.reviewFirst),
            const SizedBox(height: 12),
            Wrap(
              key: sourceChoicesKey,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final choice in state.sourceChoices) _SourceChoiceButton(choice: choice),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _summaryText(state),
              key: previewSummaryKey,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (state.isEmpty)
              const Text(ImageStagingPreviewCopy.empty)
            else
              for (final item in state.items) _PreviewItemTile(item: item),
          ],
        ),
      ),
    );
  }

  static String _summaryText(ImageStagingPreviewState state) {
    if (state.isEmpty) return '待審核：0，處理中：0';
    return '待審核：${state.readyCount}，處理中：${state.pendingCount}';
  }
}

class _SourceChoiceButton extends StatelessWidget {
  const _SourceChoiceButton({required this.choice});

  final ImageSourceChoice choice;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: _keyFor(choice.option),
      onPressed: choice.enabled ? () {} : null,
      icon: Icon(_iconFor(choice.option)),
      label: Text(choice.label),
    );
  }

  static Key _keyFor(ImageSourceOption option) {
    switch (option) {
      case ImageSourceOption.camera:
        return ImageStagingPreviewCard.cameraChoiceKey;
      case ImageSourceOption.gallery:
        return ImageStagingPreviewCard.galleryChoiceKey;
      case ImageSourceOption.manual:
        return ImageStagingPreviewCard.manualChoiceKey;
    }
  }

  static IconData _iconFor(ImageSourceOption option) {
    switch (option) {
      case ImageSourceOption.camera:
        return Icons.camera_alt_outlined;
      case ImageSourceOption.gallery:
        return Icons.photo_library_outlined;
      case ImageSourceOption.manual:
        return Icons.edit_note_outlined;
    }
  }
}

class _PreviewItemTile extends StatelessWidget {
  const _PreviewItemTile({required this.item});

  final ImageStagingPreviewItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_kindIcon(item.kind)),
      title: Text(item.title),
      subtitle: Text('${_statusLabel(item.status)}｜${item.summary}'),
      trailing: _PreviewStatusChip(label: _statusLabel(item.status)),
    );
  }

  static IconData _kindIcon(ImageStagingPreviewKind kind) {
    switch (kind) {
      case ImageStagingPreviewKind.invoice:
        return Icons.receipt_long_outlined;
      case ImageStagingPreviewKind.product:
        return Icons.shopping_bag_outlined;
    }
  }
}

class _PreviewStatusChip extends StatelessWidget {
  const _PreviewStatusChip({required this.label});

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

String _statusLabel(ImageStagingPreviewStatus status) {
  switch (status) {
    case ImageStagingPreviewStatus.empty:
      return '尚未建立';
    case ImageStagingPreviewStatus.pending:
      return '處理中';
    case ImageStagingPreviewStatus.ready:
      return '待審核';
    case ImageStagingPreviewStatus.rejected:
      return '已退回';
    case ImageStagingPreviewStatus.converted:
      return '已轉換';
  }
}
