import 'package:flutter/material.dart';

import 'draft_storage_ui_gate.dart';

class DraftStorageUiGateCard extends StatelessWidget {
  const DraftStorageUiGateCard({super.key, this.config = DraftStorageUiGateConfig.disabled});

  static const Key cardKey = Key('draft_storage_ui_gate_card');
  static const Key hiddenStateKey = Key('draft_storage_ui_gate_hidden_state');
  static const Key gatedStateKey = Key('draft_storage_ui_gate_gated_state');
  static const Key apkNoticeKey = Key('draft_storage_ui_gate_apk_notice');
  static const Key openActionKey = Key('draft_storage_ui_gate_open_action');
  static const Key writeActionKey = Key('draft_storage_ui_gate_write_action');

  final DraftStorageUiGateConfig config;

  bool get canShowLiveUiAction => false;
  bool get canMutateRuntimeStorage => false;
  bool get canCreateFinalRecordAutomatically => false;

  @override
  Widget build(BuildContext context) {
    const service = DraftStorageUiGateService();
    final result = service.evaluate(config);
    final theme = Theme.of(context);
    return Card(
      key: cardKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('草稿儲存 UI Gate', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                _GateChip(label: _modeLabel(result.mode)),
              ],
            ),
            const SizedBox(height: 8),
            Text(result.message, key: result.requiresManualApkValidation ? apkNoticeKey : _stateKey(result.mode)),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(key: openActionKey, onPressed: null, child: Text('開啟草稿清單')),
                OutlinedButton(key: writeActionKey, onPressed: null, child: Text('寫入草稿')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Key _stateKey(DraftStorageUiMode mode) {
    switch (mode) {
      case DraftStorageUiMode.hidden:
        return hiddenStateKey;
      case DraftStorageUiMode.gated:
      case DraftStorageUiMode.ready:
        return gatedStateKey;
    }
  }

  static String _modeLabel(DraftStorageUiMode mode) {
    switch (mode) {
      case DraftStorageUiMode.hidden:
        return 'Hidden';
      case DraftStorageUiMode.gated:
        return 'Gated';
      case DraftStorageUiMode.ready:
        return 'Ready';
    }
  }
}

class _GateChip extends StatelessWidget {
  const _GateChip({required this.label});

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
