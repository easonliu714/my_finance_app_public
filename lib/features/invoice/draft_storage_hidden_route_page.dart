import 'package:flutter/material.dart';

import 'draft_storage_ui_gate.dart';
import 'draft_storage_ui_gate_card.dart';

class DraftStorageHiddenRoutePage extends StatelessWidget {
  const DraftStorageHiddenRoutePage({super.key, this.config = DraftStorageUiGateConfig.disabled});

  static const String routePath = '/_internal/draft-storage-placeholder';
  static const String routeName = 'draft-storage-placeholder';
  static const bool isVisibleNavigationEntry = false;
  static const DraftStorageUiGateConfig defaultGateConfig = DraftStorageUiGateConfig.disabled;

  final DraftStorageUiGateConfig config;

  bool get canShowVisibleNavigationEntry => false;
  bool get canRunLiveUiAction => false;
  bool get canMutateRuntimeStorage => false;
  bool get canCreateFinalRecordAutomatically => false;
  bool get requiresManualApkValidation => config.enabled || config.liveUiIntent || config.runtimeStorageIntent || config.devicePermissionIntent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('草稿儲存 Gate')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: DraftStorageUiGateCard(config: config),
      ),
    );
  }
}
