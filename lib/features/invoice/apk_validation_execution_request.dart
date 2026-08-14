import 'apk_validation_record.dart';

enum ApkValidationExecutionStatus { pending, completed, cancelled }

class ApkValidationEvidenceRequirement {
  const ApkValidationEvidenceRequirement({
    required this.id,
    required this.description,
    this.required = true,
  });

  final String id;
  final String description;
  final bool required;
}

class ApkValidationExecutionRequest {
  const ApkValidationExecutionRequest({
    required this.phase,
    required this.requestedBuildVersion,
    required this.status,
    required this.validationItemIds,
    required this.evidenceRequirements,
    this.submitterNote,
    this.validationRecord,
  });

  final String phase;
  final String requestedBuildVersion;
  final ApkValidationExecutionStatus status;
  final List<String> validationItemIds;
  final List<ApkValidationEvidenceRequirement> evidenceRequirements;
  final String? submitterNote;
  final ApkValidationRecord? validationRecord;

  bool get hasRequiredEvidencePlan {
    return evidenceRequirements.any((requirement) => requirement.required);
  }

  bool get hasPassedValidationRecord {
    return validationRecord?.isReadyForVisibleEntryReview ?? false;
  }

  bool get isReadyForVisibleEntryReview {
    return status == ApkValidationExecutionStatus.completed && hasRequiredEvidencePlan && hasPassedValidationRecord;
  }

  bool get blocksVisibleEntryEnablement => !isReadyForVisibleEntryReview;
  bool get requiresManualReview => true;
  bool get canEnableGateAutomatically => false;
  bool get canCreateFinalRecordAutomatically => false;

  static const ApkValidationExecutionRequest pending = ApkValidationExecutionRequest(
    phase: 'P4.10.21',
    requestedBuildVersion: '4.10.21+304',
    status: ApkValidationExecutionStatus.pending,
    validationItemIds: <String>[
      'install_and_open',
      'hidden_route_absent_from_navigation',
      'actions_remain_disabled',
      'no_runtime_storage_mutation',
    ],
    evidenceRequirements: <ApkValidationEvidenceRequirement>[
      ApkValidationEvidenceRequirement(id: 'apk_build_identifier', description: 'Record APK build version and source commit.'),
      ApkValidationEvidenceRequirement(id: 'navigation_observation', description: 'Confirm no visible navigation entry is exposed.'),
      ApkValidationEvidenceRequirement(id: 'action_state_observation', description: 'Confirm placeholder actions remain disabled.'),
      ApkValidationEvidenceRequirement(id: 'reviewer_note', description: 'Record manual reviewer note.'),
    ],
  );
}

class ApkValidationExecutionRequestCopy {
  const ApkValidationExecutionRequestCopy._();

  static const String requestOnly = 'APK validation execution request only; no visible entry is enabled.';
  static const String passedRecordRequired = 'A passed APK validation record is required before visible entry enablement review.';
}
