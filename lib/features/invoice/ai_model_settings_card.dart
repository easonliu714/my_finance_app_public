import 'package:flutter/material.dart';

import 'ai_model_entry_rotation.dart';
import 'gemini_model_settings.dart';

class AiModelSettingsCard extends StatelessWidget {
  const AiModelSettingsCard({
    super.key,
    this.settings = const GeminiModelSettings(),
    this.rotationState = const AiModelEntryRotationState(),
  });

  static const Key cardKey = Key('ai_model_settings_card');
  static const Key loadModelsButtonKey = Key('ai_model_load_models_button');
  static const Key testButtonKey = Key('ai_model_test_button');
  static const Key activeEntryKey = Key('ai_model_active_entry');
  static const Key entryStatusKey = Key('ai_model_entry_status');
  static const Key fallbackKey = Key('ai_model_fallback_status');

  final GeminiModelSettings settings;
  final AiModelEntryRotationState rotationState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeEntry = rotationState.activeEntry;
    final unavailableCount = rotationState.entries.where((entry) => entry.shouldRotateAway).length;
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
                const Icon(Icons.auto_awesome, color: Colors.deepPurple),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI 模型設定',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                _AiModelStatusChip(label: _statusChipLabel(activeEntry)),
              ],
            ),
            const SizedBox(height: 8),
            const Text('用於商品拍照辨識、發票影像辨識與參考價格建議。'),
            const SizedBox(height: 8),
            const Text('此階段只建立設定外觀與模型選擇基礎，不會連線或上傳影像。'),
            const SizedBox(height: 12),
            Text('目前模型：${settings.selectedModel.label}', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              activeEntry == null ? '目前項目：尚未設定' : '目前項目：${activeEntry.maskedLabel}',
              key: activeEntryKey,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '狀態：${_statusLabel(activeEntry?.status)}',
              key: entryStatusKey,
            ),
            const SizedBox(height: 4),
            Text(
              _fallbackText(activeEntry: activeEntry, total: rotationState.entries.length, unavailable: unavailableCount),
              key: fallbackKey,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: loadModelsButtonKey,
                  onPressed: null,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('載入模型'),
                ),
                FilledButton.tonalIcon(
                  key: testButtonKey,
                  onPressed: null,
                  icon: const Icon(Icons.bolt_outlined),
                  label: const Text('測試'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _statusChipLabel(AiModelEntry? activeEntry) {
    if (activeEntry == null) return '待設定';
    switch (activeEntry.status) {
      case AiModelEntryStatus.unknown:
        return '待確認';
      case AiModelEntryStatus.usable:
        return '可用';
      case AiModelEntryStatus.rejected:
      case AiModelEntryStatus.quotaExhausted:
      case AiModelEntryStatus.disabled:
        return '需切換';
    }
  }

  static String _statusLabel(AiModelEntryStatus? status) {
    switch (status) {
      case null:
        return '尚未設定';
      case AiModelEntryStatus.unknown:
        return '尚未確認';
      case AiModelEntryStatus.usable:
        return '可用';
      case AiModelEntryStatus.rejected:
        return '已拒絕';
      case AiModelEntryStatus.quotaExhausted:
        return '額度已用完';
      case AiModelEntryStatus.disabled:
        return '已停用';
    }
  }

  static String _fallbackText({required AiModelEntry? activeEntry, required int total, required int unavailable}) {
    if (total == 0) return '備援狀態：尚無可切換項目';
    if (activeEntry == null) return '備援狀態：目前沒有可用項目';
    final available = total - unavailable;
    return '備援狀態：$available/$total 可用，$unavailable 個已跳過';
  }
}

class _AiModelStatusChip extends StatelessWidget {
  const _AiModelStatusChip({required this.label});

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
