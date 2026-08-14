import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/draft_persistence_plan.dart';

void main() {
  test('draft persistence plan exposes deterministic collection and fields', () {
    expect(DraftPersistencePlan.phase, 'P4.10.10');
    expect(DraftPersistencePlan.collectionName, 'image_review_drafts');
    expect(DraftPersistencePlan.fieldNames, containsAll(<String>['id', 'draft_kind', 'review_state', 'created_at', 'updated_at']));
    expect(DraftPersistencePlan.lookupNames, contains('image_review_drafts_by_kind_state'));
  });

  test('draft persistence plan separates draft kinds and review states', () {
    expect(DraftPersistencePlan.allowedDraftKinds, <String>['invoice', 'transaction']);
    expect(DraftPersistencePlan.allowedReviewStates, contains('pending_edit'));
    expect(DraftPersistencePlan.allowedReviewStates, contains('confirmed_for_manual_review'));
  });

  test('draft persistence plan stays local and review-first', () {
    expect(DraftPersistencePlan.isLocalOnly, isTrue);
    expect(DraftPersistencePlan.requiresManualReview, isTrue);
    expect(DraftPersistencePlan.appliesRuntimeStorageChange, isFalse);
    expect(DraftPersistencePlan.canCreateFinalRecordAutomatically, isFalse);
  });

  test('draft persistence plan copy documents boundary', () {
    expect(DraftPersistencePlanCopy.planOnly, contains('欄位規劃'));
    expect(DraftPersistencePlanCopy.reviewBoundary, contains('不會自動建立正式紀錄'));
  });
}
