enum ApkValidationOutcome { pending, passed, failed, blocked }

class ApkValidationCheckResult {
  const ApkValidationCheckResult({required this.id, required this.passed, this.note});

  final String id;
  final bool passed;
  final String? note;
}

class ApkValidationRecord {
  const ApkValidationRecord({
    required this.phase,
    required this.buildVersion,
    required this.outcome,
    required this.checks,
    this.reviewerNote,
  });

  final String phase;
  final String buildVersion;
  final ApkValidationOutcome outcome;
  final List<ApkValidationCheckResult> checks;
  final String? reviewerNote;

  bool get hasAllRequiredChecks => checks.isNotEmpty && checks.every((check) => check.passed);
  bool get isReadyForVisibleEntryReview => outcome == ApkValidationOutcome.passed && hasAllRequiredChecks;
  bool get blocksVisibleEntryEnablement => outcome != ApkValidationOutcome.passed || !hasAllRequiredChecks;
  bool get requiresManualReview => true;
  bool get canEnableGateAutomatically => false;
  bool get canCreateFinalRecordAutomatically => false;

  static const ApkValidationRecord pending = ApkValidationRecord(
    phase: 'P4.10.20',
    buildVersion: '4.10.20+303',
    outcome: ApkValidationOutcome.pending,
    checks: <ApkValidationCheckResult>[],
  );
}

class ApkValidationRecordCopy {
  const ApkValidationRecordCopy._();

  static const String templateOnly = 'APK validation record template only; no visible entry is enabled.';
  static const String validationRequired = 'Manual APK validation is required before visible entry enablement.';
}
