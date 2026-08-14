enum DraftStorageUiMode { hidden, gated, ready }

class DraftStorageUiGateConfig {
  const DraftStorageUiGateConfig({
    this.enabled = false,
    this.liveUiIntent = false,
    this.runtimeStorageIntent = false,
    this.devicePermissionIntent = false,
  });

  final bool enabled;
  final bool liveUiIntent;
  final bool runtimeStorageIntent;
  final bool devicePermissionIntent;

  static const DraftStorageUiGateConfig disabled = DraftStorageUiGateConfig();
}

class DraftStorageUiGateResult {
  const DraftStorageUiGateResult({
    required this.mode,
    required this.requiresManualApkValidation,
    required this.message,
  });

  final DraftStorageUiMode mode;
  final bool requiresManualApkValidation;
  final String message;

  bool get isLocalOnly => true;
  bool get requiresManualReview => true;
  bool get canShowLiveUiAction => false;
  bool get canMutateRuntimeStorage => false;
  bool get canCreateFinalRecordAutomatically => false;
}

class DraftStorageUiGateService {
  const DraftStorageUiGateService();

  DraftStorageUiGateResult evaluate(DraftStorageUiGateConfig config) {
    final requiresManualApkValidation = config.enabled || config.liveUiIntent || config.runtimeStorageIntent || config.devicePermissionIntent;
    if (!config.enabled) {
      return DraftStorageUiGateResult(
        mode: DraftStorageUiMode.hidden,
        requiresManualApkValidation: requiresManualApkValidation,
        message: requiresManualApkValidation ? 'Gate is disabled, but APK validation is required before enabling the UI path.' : 'Gate is disabled; no manual APK validation is required yet.',
      );
    }
    return const DraftStorageUiGateResult(
      mode: DraftStorageUiMode.gated,
      requiresManualApkValidation: true,
      message: 'Gate is enabled only for validation; keep user actions blocked until APK validation is complete.',
    );
  }
}

class DraftStorageUiGateCopy {
  const DraftStorageUiGateCopy._();

  static const String disabledByDefault = 'Draft storage UI gate is disabled by default.';
  static const String apkRequiredWhenEnabled = 'Manual APK validation is required before enabling visible UI or runtime storage paths.';
}
