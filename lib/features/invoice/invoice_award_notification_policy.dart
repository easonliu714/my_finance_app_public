/// Pure Issue #13 notification decision contract.
///
/// This policy has no platform side effects. It only decides whether a local
/// reminder is allowed. Network refresh and formal accounting writes are
/// deliberately outside this contract.
class InvoiceAwardNotificationPolicy {
  const InvoiceAwardNotificationPolicy();

  InvoiceAwardNotificationDecision decide({
    required bool automaticRefreshConsented,
    required bool notificationPermissionGranted,
    required bool localReminderEnabled,
    required bool awardRefreshDue,
    required bool currentGeneralDatasetValidated,
    required bool currentCloudDatasetValidated,
  }) {
    final currentDatasetsComplete =
        currentGeneralDatasetValidated && currentCloudDatasetValidated;

    // Opted-in automatic refresh owns the due path. Do not duplicate it with a
    // local manual-refresh reminder.
    if (automaticRefreshConsented ||
        !notificationPermissionGranted ||
        !localReminderEnabled ||
        !awardRefreshDue ||
        currentDatasetsComplete) {
      return InvoiceAwardNotificationDecision.none;
    }

    return InvoiceAwardNotificationDecision.remindToOpenAwardCheck;
  }
}

enum InvoiceAwardNotificationDecision {
  none,
  remindToOpenAwardCheck,
}

extension InvoiceAwardNotificationDecisionSafety
    on InvoiceAwardNotificationDecision {
  bool get mayFetchAwardNumbers => false;
  bool get mayCreateFormalTransaction => false;
  bool get mayConfigureMofRemittance => false;
}
