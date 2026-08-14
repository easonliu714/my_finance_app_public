enum DraftStorageVisibleEntryLocation { dashboard, myPage, invoicePage, accountPage }

enum DraftStorageVisibleEntryDecision { notApproved, needsApkValidation, approvedAfterValidation }

class DraftStorageVisibleEntryCandidate {
  const DraftStorageVisibleEntryCandidate({required this.location, required this.label, required this.riskNote});

  final DraftStorageVisibleEntryLocation location;
  final String label;
  final String riskNote;
}

class DraftStorageVisibleEntryReviewResult {
  const DraftStorageVisibleEntryReviewResult({
    required this.decision,
    required this.candidates,
    required this.message,
  });

  final DraftStorageVisibleEntryDecision decision;
  final List<DraftStorageVisibleEntryCandidate> candidates;
  final String message;

  bool get keepsVisibleEntryDisabled => decision == DraftStorageVisibleEntryDecision.notApproved;
  bool get requiresManualApkValidationBeforeEnablement => true;
  bool get canEnableGateAutomatically => false;
  bool get canMutateRuntimeStorage => false;
  bool get canCreateFinalRecordAutomatically => false;
}

class DraftStorageVisibleEntryDesignReview {
  const DraftStorageVisibleEntryDesignReview._();

  static const List<DraftStorageVisibleEntryCandidate> candidateEntries = <DraftStorageVisibleEntryCandidate>[
    DraftStorageVisibleEntryCandidate(
      location: DraftStorageVisibleEntryLocation.myPage,
      label: 'My page diagnostics section',
      riskNote: 'Lowest user-flow risk, but still requires APK validation before enablement.',
    ),
    DraftStorageVisibleEntryCandidate(
      location: DraftStorageVisibleEntryLocation.invoicePage,
      label: 'Invoice workflow section',
      riskNote: 'Closest to intended workflow, requires stronger copy and APK validation.',
    ),
    DraftStorageVisibleEntryCandidate(
      location: DraftStorageVisibleEntryLocation.dashboard,
      label: 'Dashboard shortcut',
      riskNote: 'High discoverability and highest accidental-use risk.',
    ),
  ];

  static DraftStorageVisibleEntryReviewResult currentReview() {
    return const DraftStorageVisibleEntryReviewResult(
      decision: DraftStorageVisibleEntryDecision.notApproved,
      candidates: candidateEntries,
      message: 'Visible entry is not approved yet; keep the route hidden and the gate disabled.',
    );
  }
}

class DraftStorageVisibleEntryDesignCopy {
  const DraftStorageVisibleEntryDesignCopy._();

  static const String reviewOnly = 'Visible entry remains in design review and is not enabled.';
  static const String apkRequired = 'Manual APK validation is required before any visible entry is enabled.';
}
