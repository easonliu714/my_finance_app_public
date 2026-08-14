import 'package:flutter/material.dart';

import 'invoice_recognition_disclaimer.dart';

enum DailyCaptureIntent {
  invoice,
  product,
}

enum DailyCaptureSource {
  camera,
  gallery,
}

class DailyCaptureEntryChoice {
  const DailyCaptureEntryChoice({
    required this.intent,
    required this.label,
    required this.description,
  });

  final DailyCaptureIntent intent;
  final String label;
  final String description;
}

class DailyCaptureSourceChoice {
  const DailyCaptureSourceChoice({
    required this.source,
    required this.label,
    required this.description,
    this.enabled = false,
  });

  final DailyCaptureSource source;
  final String label;
  final String description;
  final bool enabled;
}

class DailyCaptureEntryState {
  const DailyCaptureEntryState({
    this.entryChoices = defaultEntryChoices,
    this.sourceChoices = defaultSourceChoices,
  });

  final List<DailyCaptureEntryChoice> entryChoices;
  final List<DailyCaptureSourceChoice> sourceChoices;

  static const List<DailyCaptureEntryChoice> defaultEntryChoices =
      <DailyCaptureEntryChoice>[
    DailyCaptureEntryChoice(
      intent: DailyCaptureIntent.invoice,
      label: '掃描發票',
      description: '辨識 QR code、發票號碼、日期、金額與對獎候選。',
    ),
    DailyCaptureEntryChoice(
      intent: DailyCaptureIntent.product,
      label: '拍商品',
      description: '辨識商品、收據或價格標籤，建立待審核交易草稿。',
    ),
  ];

  static const List<DailyCaptureSourceChoice> defaultSourceChoices =
      <DailyCaptureSourceChoice>[
    DailyCaptureSourceChoice(
      source: DailyCaptureSource.camera,
      label: '開啟相機',
      description: '開啟相機後，只會建立本機待審核影像項目。',
      enabled: true,
    ),
    DailyCaptureSourceChoice(
      source: DailyCaptureSource.gallery,
      label: '從相簿選擇',
      description: '從相簿選擇後，只會建立本機待審核影像項目。',
      enabled: true,
    ),
  ];
}

class DailyCaptureEntryCard extends StatelessWidget {
  const DailyCaptureEntryCard({
    super.key,
    this.state = const DailyCaptureEntryState(),
    this.onCameraSelected,
    this.onGallerySelected,
  });

  static const Key cardKey = Key('daily_capture_entry_card');
  static const Key invoiceChoiceKey = Key('daily_capture_invoice_choice');
  static const Key productChoiceKey = Key('daily_capture_product_choice');
  static const Key cameraSourceKey = Key('daily_capture_camera_source');
  static const Key gallerySourceKey = Key('daily_capture_gallery_source');
  static const Key disclaimerKey = Key('daily_capture_invoice_disclaimer');

  final DailyCaptureEntryState state;
  final VoidCallback? onCameraSelected;
  final VoidCallback? onGallerySelected;

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
                const Icon(Icons.add_a_photo_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '拍照記帳',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const _CaptureChip(label: '待審核'),
              ],
            ),
            const SizedBox(height: 8),
            const Text('日常記帳入口：先選擇掃描發票或拍商品，再選擇相機或相簿。'),
            const SizedBox(height: 8),
            const Text('相機與相簿只會建立本機待審核項目，不會上傳影像、不會自動建立交易。'),
            const SizedBox(height: 8),
            Text(
              InvoiceRecognitionDisclaimer.text,
              key: disclaimerKey,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '辨識類型',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            for (final choice in state.entryChoices)
              _EntryChoiceTile(choice: choice),
            const SizedBox(height: 12),
            Text(
              '影像來源',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final choice in state.sourceChoices)
                  _SourceChoiceButton(
                    choice: choice,
                    onCameraSelected: onCameraSelected,
                    onGallerySelected: onGallerySelected,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryChoiceTile extends StatelessWidget {
  const _EntryChoiceTile({required this.choice});

  final DailyCaptureEntryChoice choice;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: _entryKey(choice.intent),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        choice.intent == DailyCaptureIntent.invoice
            ? Icons.receipt_long_outlined
            : Icons.shopping_bag_outlined,
      ),
      title: Text(choice.label),
      subtitle: Text(choice.description),
      trailing: const _CaptureChip(label: '可選'),
    );
  }

  static Key _entryKey(DailyCaptureIntent intent) {
    switch (intent) {
      case DailyCaptureIntent.invoice:
        return DailyCaptureEntryCard.invoiceChoiceKey;
      case DailyCaptureIntent.product:
        return DailyCaptureEntryCard.productChoiceKey;
    }
  }
}

class _SourceChoiceButton extends StatelessWidget {
  const _SourceChoiceButton({
    required this.choice,
    this.onCameraSelected,
    this.onGallerySelected,
  });

  final DailyCaptureSourceChoice choice;
  final VoidCallback? onCameraSelected;
  final VoidCallback? onGallerySelected;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: _sourceKey(choice.source),
      onPressed: choice.enabled ? _actionFor(choice.source) : null,
      icon: Icon(
        choice.source == DailyCaptureSource.camera
            ? Icons.camera_alt_outlined
            : Icons.photo_library_outlined,
      ),
      label: Text(choice.label),
    );
  }

  VoidCallback? _actionFor(DailyCaptureSource source) {
    switch (source) {
      case DailyCaptureSource.camera:
        return onCameraSelected;
      case DailyCaptureSource.gallery:
        return onGallerySelected;
    }
  }

  static Key _sourceKey(DailyCaptureSource source) {
    switch (source) {
      case DailyCaptureSource.camera:
        return DailyCaptureEntryCard.cameraSourceKey;
      case DailyCaptureSource.gallery:
        return DailyCaptureEntryCard.gallerySourceKey;
    }
  }
}

class _CaptureChip extends StatelessWidget {
  const _CaptureChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.secondary;
    return Chip(
      label: Text(label),
      side: BorderSide(color: color),
      labelStyle: TextStyle(
        color: color,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}
