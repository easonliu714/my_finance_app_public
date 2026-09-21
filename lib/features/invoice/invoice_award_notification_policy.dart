/// Pure Issue #13 notification contract.
///
/// This policy has no network, matching, redemption, or accounting authority.
/// It only decides whether an already-due local reminder may be presented and
/// defines the stable route target for the Award Check page.
class InvoiceAwardNotificationPolicy {
  const InvoiceAwardNotificationPolicy();

  static const String awardCheckRoute = '/invoice/award-check';

  bool shouldPresentDueReminder({
    required bool automaticRefreshConsented,
    required bool notificationPermissionGranted,
    required bool awardReminderEnabled,
    required bool publicationDue,
    required bool currentGeneralPromoted,
    required bool currentCloudExclusivePromoted,
  }) {
    if (automaticRefreshConsented ||
        !notificationPermissionGranted ||
        !awardReminderEnabled ||
        !publicationDue) {
      return false;
    }
    return !(currentGeneralPromoted && currentCloudExclusivePromoted);
  }

  /// Notification taps only navigate to the read-only Award Check surface.
  /// They never authorize background acquisition, matching, redemption, or a
  /// formal transaction write.
  String get reminderRoute => awardCheckRoute;

  bool get canFetchOfficialDataset => false;
  bool get canMatchInvoice => false;
  bool get canRedeemPrize => false;
  bool get canConfigureMofRemittance => false;
  bool get canCreateFormalTransaction => false;
}
