import 'package:flutter/material.dart';

import 'full_restore_preview_service.dart';

class BackupPreviewConfirmationGate extends StatefulWidget {
  const BackupPreviewConfirmationGate({super.key, required this.preview, this.onCommitRestore});

  final FullRestoreBackupPreview preview;
  final ValueChanged<FullRestoreBackupPreview>? onCommitRestore;

  @override
  State<BackupPreviewConfirmationGate> createState() => _BackupPreviewConfirmationGateState();
}

class _BackupPreviewConfirmationGateState extends State<BackupPreviewConfirmationGate> {
  bool _checkedMetadata = false;
  bool _checkedDiff = false;
  bool _checkedReadOnly = false;

  bool get _readyForNextStep => _checkedMetadata && _checkedDiff && _checkedReadOnly;

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final metadata = preview.metadata;
    if (!preview.isValid || metadata == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('確認門檻', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('候選檔案：${preview.fileName}'),
            Text('版本：${metadata.appVersion}'),
            Text('資料表數：${preview.tableRowCounts.length}'),
            const SizedBox(height: 8),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _checkedMetadata,
              onChanged: (value) => setState(() => _checkedMetadata = value ?? false),
              title: const Text('我已確認 metadata 與來源檔案。'),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _checkedDiff,
              onChanged: (value) => setState(() => _checkedDiff = value ?? false),
              title: const Text('我已確認 table diff summary。'),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _checkedReadOnly,
              onChanged: (value) => setState(() => _checkedReadOnly = value ?? false),
              title: const Text('我了解此步驟仍為預覽；下一步會要求輸入 RESTORE 才能覆蓋資料。'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _readyForNextStep ? () => widget.onCommitRestore?.call(preview) : null,
              icon: const Icon(Icons.lock_open_outlined),
              label: Text(_readyForNextStep ? '進入正式還原確認' : '請先完成確認'),
            ),
          ],
        ),
      ),
    );
  }
}
