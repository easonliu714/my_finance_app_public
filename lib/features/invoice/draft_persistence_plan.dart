class DraftPersistencePlan {
  const DraftPersistencePlan._();

  static const String phase = 'P4.10.10';
  static const String collectionName = 'image_review_drafts';
  static const List<String> allowedDraftKinds = <String>['invoice', 'transaction'];
  static const List<String> allowedReviewStates = <String>['pending_edit', 'discarded', 'confirmed_for_manual_review'];
  static const List<String> fieldNames = <String>[
    'id',
    'draft_kind',
    'review_state',
    'source_candidate_kind',
    'source_candidate_label',
    'source_candidate_amount',
    'source_candidate_note',
    'review_note',
    'created_at',
    'updated_at',
  ];
  static const List<String> lookupNames = <String>[
    'image_review_drafts_by_state',
    'image_review_drafts_by_kind_state',
    'image_review_drafts_by_created_at',
  ];

  static const bool isLocalOnly = true;
  static const bool requiresManualReview = true;
  static const bool appliesRuntimeStorageChange = false;
  static const bool canCreateFinalRecordAutomatically = false;
}

class DraftPersistencePlanCopy {
  const DraftPersistencePlanCopy._();

  static const String planOnly = '本階段只定義草稿持久化欄位規劃，不套用執行期儲存變更。';
  static const String reviewBoundary = '草稿資料只保存本機待審核資料，不會自動建立正式紀錄。';
}
