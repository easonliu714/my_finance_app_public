import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/apk_validation_checklist.dart';

void main() {
  test('APK validation checklist exposes deterministic required items', () {
    expect(ApkValidationChecklistService.requiredItems, contains(ApkValidationChecklistItem.hiddenRouteReachable));
    expect(ApkValidationChecklistService.requiredItems, contains(ApkValidationChecklistItem.featureGateDisabledByDefault));
    expect(ApkValidationChecklistService.requiredItems, contains(ApkValidationChecklistItem.runtimeStorageWriteBlocked));
  });

  test('incomplete checklist blocks visible entry enablement', () {
    const service = ApkValidationChecklistService();

    final result = service.evaluate(
      const ApkValidationChecklistInput(completedItems: <ApkValidationChecklistItem>{ApkValidationChecklistItem.hiddenRouteReachable}),
    );

    expect(result.complete, isFalse);
    expect(result.readyForManualReview, isFalse);
    expect(result.missingItems, contains(ApkValidationChecklistItem.featureGateDisabledByDefault));
    expect(result.canEnableVisibleEntryAutomatically, isFalse);
  });

  test('complete checklist is ready for manual review only', () {
    const service = ApkValidationChecklistService();

    final result = service.evaluate(
      const ApkValidationChecklistInput(completedItems: ApkValidationChecklistService.requiredItems),
    );

    expect(result.complete, isTrue);
    expect(result.readyForManualReview, isTrue);
    expect(result.missingItems, isEmpty);
    expect(result.canEnableVisibleEntryAutomatically, isFalse);
    expect(result.canMutateRuntimeStorage, isFalse);
    expect(result.canCreateFinalRecordAutomatically, isFalse);
  });

  test('APK validation checklist copy documents boundary', () {
    expect(ApkValidationChecklistCopy.checklistOnly, contains('checklist only'));
    expect(ApkValidationChecklistCopy.noAutomaticEnablement, contains('cannot be enabled automatically'));
  });
}
