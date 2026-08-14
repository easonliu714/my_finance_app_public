import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/draft_storage_ui_gate.dart';

void main() {
  test('draft storage UI gate is disabled by default', () {
    const service = DraftStorageUiGateService();

    final result = service.evaluate(DraftStorageUiGateConfig.disabled);

    expect(result.mode, DraftStorageUiMode.hidden);
    expect(result.requiresManualApkValidation, isFalse);
    expect(result.isLocalOnly, isTrue);
    expect(result.requiresManualReview, isTrue);
    expect(result.canShowLiveUiAction, isFalse);
    expect(result.canMutateRuntimeStorage, isFalse);
    expect(result.canCreateFinalRecordAutomatically, isFalse);
  });

  test('live UI intent requires manual APK validation before enablement', () {
    const service = DraftStorageUiGateService();

    final result = service.evaluate(
      const DraftStorageUiGateConfig(liveUiIntent: true),
    );

    expect(result.mode, DraftStorageUiMode.hidden);
    expect(result.requiresManualApkValidation, isTrue);
    expect(result.canShowLiveUiAction, isFalse);
  });

  test('enabled gate remains gated and keeps actions blocked', () {
    const service = DraftStorageUiGateService();

    final result = service.evaluate(
      const DraftStorageUiGateConfig(enabled: true),
    );

    expect(result.mode, DraftStorageUiMode.gated);
    expect(result.requiresManualApkValidation, isTrue);
    expect(result.canShowLiveUiAction, isFalse);
    expect(result.canMutateRuntimeStorage, isFalse);
    expect(result.canCreateFinalRecordAutomatically, isFalse);
  });

  test('gate copy documents APK validation boundary', () {
    expect(DraftStorageUiGateCopy.disabledByDefault, contains('disabled by default'));
    expect(DraftStorageUiGateCopy.apkRequiredWhenEnabled, contains('Manual APK validation'));
  });
}
