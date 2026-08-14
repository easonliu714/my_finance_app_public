enum StorageUiIntegrationReadinessGate {
  dryRunPayloadValidation,
  guardedWritePrototype,
  rollbackPlanReviewed,
  ciGreen,
  apkValidationPlanReady,
}

class StorageUiIntegrationCheckpointInput {
  const StorageUiIntegrationCheckpointInput({
    required this.completedGates,
    required this.liveUiWiringPlanned,
    required this.runtimeStorageMutationPlanned,
    required this.devicePermissionFlowTouched,
  });

  final Set<StorageUiIntegrationReadinessGate> completedGates;
  final bool liveUiWiringPlanned;
  final bool runtimeStorageMutationPlanned;
  final bool devicePermissionFlowTouched;
}

class StorageUiIntegrationCheckpointResult {
  const StorageUiIntegrationCheckpointResult({
    required this.readyForLiveUiWiring,
    required this.requiresManualApkValidation,
    required this.missingGates,
    required this.message,
  });

  final bool readyForLiveUiWiring;
  final bool requiresManualApkValidation;
  final Set<StorageUiIntegrationReadinessGate> missingGates;
  final String message;

  bool get isLocalOnly => true;
  bool get requiresManualReview => true;
  bool get canRunLiveUiAction => false;
  bool get canMutateRuntimeStorage => false;
  bool get canCreateFinalRecordAutomatically => false;
}

class StorageUiIntegrationCheckpointService {
  const StorageUiIntegrationCheckpointService();

  static const Set<StorageUiIntegrationReadinessGate> requiredGates = <StorageUiIntegrationReadinessGate>{
    StorageUiIntegrationReadinessGate.dryRunPayloadValidation,
    StorageUiIntegrationReadinessGate.guardedWritePrototype,
    StorageUiIntegrationReadinessGate.rollbackPlanReviewed,
    StorageUiIntegrationReadinessGate.ciGreen,
    StorageUiIntegrationReadinessGate.apkValidationPlanReady,
  };

  StorageUiIntegrationCheckpointResult evaluate(StorageUiIntegrationCheckpointInput input) {
    final missingGates = requiredGates.difference(input.completedGates);
    final requiresManualApkValidation = input.liveUiWiringPlanned || input.runtimeStorageMutationPlanned || input.devicePermissionFlowTouched;
    return StorageUiIntegrationCheckpointResult(
      readyForLiveUiWiring: missingGates.isEmpty,
      requiresManualApkValidation: requiresManualApkValidation,
      missingGates: missingGates,
      message: requiresManualApkValidation ? '需要手動 APK 實裝驗證。' : '目前仍為 checkpoint-only，暫不需要手動 APK 實裝驗證。',
    );
  }
}

class StorageUiIntegrationCheckpointCopy {
  const StorageUiIntegrationCheckpointCopy._();

  static const String checkpointOnly = '本階段只建立 UI integration checkpoint，不接 live UI flow。';
  static const String apkGate = '若開始 live UI wiring、runtime storage mutation 或 device permission flow，必須手動 APK 實裝驗證。';
}
