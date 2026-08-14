class StorageRollforwardStep {
  const StorageRollforwardStep({required this.id, required this.description, required this.rollbackStepId});

  final String id;
  final String description;
  final String rollbackStepId;
}

class StorageRollbackStep {
  const StorageRollbackStep({required this.id, required this.description});

  final String id;
  final String description;
}

class StorageVerificationCheck {
  const StorageVerificationCheck({required this.id, required this.description});

  final String id;
  final String description;
}

class StorageRollforwardPlan {
  const StorageRollforwardPlan._();

  static const String phase = 'P4.10.13';
  static const String planId = 'p4_10_13_draft_persistence_storage_plan';
  static const int targetStorageVersion = 41013;

  static const List<StorageRollforwardStep> forwardSteps = <StorageRollforwardStep>[
    StorageRollforwardStep(id: 'create_image_review_drafts', description: 'Create local draft review storage shape.', rollbackStepId: 'drop_image_review_drafts'),
    StorageRollforwardStep(id: 'index_draft_review_state', description: 'Add lookup for draft review state.', rollbackStepId: 'drop_index_draft_review_state'),
    StorageRollforwardStep(id: 'index_draft_kind_state', description: 'Add lookup for draft kind and review state.', rollbackStepId: 'drop_index_draft_kind_state'),
  ];

  static const List<StorageRollbackStep> rollbackSteps = <StorageRollbackStep>[
    StorageRollbackStep(id: 'drop_image_review_drafts', description: 'Remove local draft review storage shape.'),
    StorageRollbackStep(id: 'drop_index_draft_review_state', description: 'Remove lookup for draft review state.'),
    StorageRollbackStep(id: 'drop_index_draft_kind_state', description: 'Remove lookup for draft kind and review state.'),
  ];

  static const List<StorageVerificationCheck> verificationChecks = <StorageVerificationCheck>[
    StorageVerificationCheck(id: 'verify_local_only_boundary', description: 'Plan remains local-only and review-first.'),
    StorageVerificationCheck(id: 'verify_required_payload_fields', description: 'Draft payload field coverage matches dry-run plan.'),
    StorageVerificationCheck(id: 'verify_no_final_record_write', description: 'Plan cannot create final records automatically.'),
  ];

  static List<String> get forwardStepIds => forwardSteps.map((step) => step.id).toList(growable: false);
  static List<String> get rollbackStepIds => rollbackSteps.map((step) => step.id).toList(growable: false);

  static bool get hasRollbackCoverage => forwardSteps.every((step) => rollbackStepIds.contains(step.rollbackStepId));
  static bool get isLocalOnly => true;
  static bool get requiresManualReview => true;
  static bool get appliesAtRuntime => false;
  static bool get canCreateFinalRecordAutomatically => false;
}

class StorageRollforwardPlanCopy {
  const StorageRollforwardPlanCopy._();

  static const String planOnly = '本階段只定義 storage rollforward plan，不套用執行期儲存變更。';
  static const String rollbackRequired = '每個 forward step 都必須有 rollback step 覆蓋。';
}
