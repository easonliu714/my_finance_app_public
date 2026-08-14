import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/visible_entry_design_review.dart';

void main() {
  test('visible entry review exposes candidate locations', () {
    final result = DraftStorageVisibleEntryDesignReview.currentReview();

    expect(result.candidates.map((candidate) => candidate.location), contains(DraftStorageVisibleEntryLocation.myPage));
    expect(result.candidates.map((candidate) => candidate.location), contains(DraftStorageVisibleEntryLocation.invoicePage));
    expect(result.candidates.map((candidate) => candidate.location), contains(DraftStorageVisibleEntryLocation.dashboard));
  });

  test('current visible entry decision keeps entry disabled', () {
    final result = DraftStorageVisibleEntryDesignReview.currentReview();

    expect(result.decision, DraftStorageVisibleEntryDecision.notApproved);
    expect(result.keepsVisibleEntryDisabled, isTrue);
    expect(result.canEnableGateAutomatically, isFalse);
  });

  test('visible entry requires manual APK validation before enablement', () {
    final result = DraftStorageVisibleEntryDesignReview.currentReview();

    expect(result.requiresManualApkValidationBeforeEnablement, isTrue);
    expect(result.canMutateRuntimeStorage, isFalse);
    expect(result.canCreateFinalRecordAutomatically, isFalse);
  });

  test('visible entry copy documents review boundary', () {
    expect(DraftStorageVisibleEntryDesignCopy.reviewOnly, contains('not enabled'));
    expect(DraftStorageVisibleEntryDesignCopy.apkRequired, contains('Manual APK validation'));
  });
}
