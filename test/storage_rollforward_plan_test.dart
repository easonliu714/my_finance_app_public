import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/storage_rollforward_plan.dart';

void main() {
  test('storage plan exposes deterministic metadata', () {
    expect(StorageRollforwardPlan.phase, 'P4.10.13');
    expect(StorageRollforwardPlan.planId, 'p4_10_13_draft_persistence_storage_plan');
    expect(StorageRollforwardPlan.targetStorageVersion, 41013);
    expect(StorageRollforwardPlan.forwardStepIds, contains('create_image_review_drafts'));
    expect(StorageRollforwardPlan.verificationChecks.map((check) => check.id), contains('verify_no_final_record_write'));
  });

  test('storage plan has paired reverse coverage', () {
    expect(StorageRollforwardPlan.rollbackStepIds, contains('drop_image_review_drafts'));
    expect(StorageRollforwardPlan.hasRollbackCoverage, isTrue);
  });

  test('storage plan stays plan-only and review-first', () {
    expect(StorageRollforwardPlan.isLocalOnly, isTrue);
    expect(StorageRollforwardPlan.requiresManualReview, isTrue);
    expect(StorageRollforwardPlan.appliesAtRuntime, isFalse);
    expect(StorageRollforwardPlan.canCreateFinalRecordAutomatically, isFalse);
  });

  test('storage plan copy documents boundaries', () {
    expect(StorageRollforwardPlanCopy.planOnly, contains('不套用執行期儲存變更'));
    expect(StorageRollforwardPlanCopy.rollbackRequired, contains('forward step'));
  });
}
