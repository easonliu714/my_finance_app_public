import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/storage_ui_integration_checkpoint.dart';

void main() {
  test('checkpoint passes when all readiness gates are complete', () {
    const service = StorageUiIntegrationCheckpointService();
    final result = service.evaluate(
      const StorageUiIntegrationCheckpointInput(
        completedGates: StorageUiIntegrationCheckpointService.requiredGates,
        liveUiWiringPlanned: false,
        runtimeStorageMutationPlanned: false,
        devicePermissionFlowTouched: false,
      ),
    );

    expect(result.readyForLiveUiWiring, isTrue);
    expect(result.requiresManualApkValidation, isFalse);
    expect(result.missingGates, isEmpty);
    expect(result.isLocalOnly, isTrue);
    expect(result.requiresManualReview, isTrue);
    expect(result.canRunLiveUiAction, isFalse);
    expect(result.canMutateRuntimeStorage, isFalse);
    expect(result.canCreateFinalRecordAutomatically, isFalse);
  });

  test('checkpoint reports missing gates', () {
    const service = StorageUiIntegrationCheckpointService();
    final result = service.evaluate(
      const StorageUiIntegrationCheckpointInput(
        completedGates: <StorageUiIntegrationReadinessGate>{
          StorageUiIntegrationReadinessGate.dryRunPayloadValidation,
        },
        liveUiWiringPlanned: false,
        runtimeStorageMutationPlanned: false,
        devicePermissionFlowTouched: false,
      ),
    );

    expect(result.readyForLiveUiWiring, isFalse);
    expect(result.missingGates, contains(StorageUiIntegrationReadinessGate.guardedWritePrototype));
    expect(result.requiresManualApkValidation, isFalse);
  });

  test('checkpoint requires APK validation when live UI or storage mutation starts', () {
    const service = StorageUiIntegrationCheckpointService();
    final result = service.evaluate(
      const StorageUiIntegrationCheckpointInput(
        completedGates: StorageUiIntegrationCheckpointService.requiredGates,
        liveUiWiringPlanned: true,
        runtimeStorageMutationPlanned: false,
        devicePermissionFlowTouched: false,
      ),
    );

    expect(result.readyForLiveUiWiring, isTrue);
    expect(result.requiresManualApkValidation, isTrue);
    expect(result.message, contains('需要手動 APK 實裝驗證'));
  });

  test('checkpoint copy documents APK gate boundary', () {
    expect(StorageUiIntegrationCheckpointCopy.checkpointOnly, contains('checkpoint'));
    expect(StorageUiIntegrationCheckpointCopy.apkGate, contains('手動 APK 實裝驗證'));
  });
}
