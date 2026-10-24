import 'invoice_award_official_dataset.dart';

/// Pure Issue #13 policy for users who did not consent to automatic refresh.
///
/// This contract never performs network I/O or creates notifications. It only
/// describes whether a local reminder may be surfaced and which official award
/// periods a user-triggered refresh must acquire. Production adapters remain
/// responsible for Ministry-of-Finance-only acquisition and local matching.
class InvoiceAwardManualRefreshPolicy {
  const InvoiceAwardManualRefreshPolicy({
    required this.automaticRefreshConsented,
  });

  final bool automaticRefreshConsented;

  /// Opt-out is a hard zero-background-network boundary.
  bool get permitsBackgroundAwardNetworkFetch => automaticRefreshConsented;

  /// A reminder is local-only and may be surfaced only when the user opted out
  /// of automatic refresh, the publication cycle is due, and app/OS settings
  /// allow notifications. It must route to Award Check rather than fetch data.
  bool shouldSurfaceLocalReminder({
    required DateTime nowLocal,
    required bool notificationPermissionGranted,
    required bool awardReminderEnabled,
    required bool currentGeneralPromoted,
    required bool currentCloudExclusivePromoted,
  }) {
    if (automaticRefreshConsented ||
        !notificationPermissionGranted ||
        !awardReminderEnabled ||
        (currentGeneralPromoted && currentCloudExclusivePromoted)) {
      return false;
    }
    return _publicationDue(nowLocal);
  }

  /// Returns periods that a user-triggered refresh still needs.
  ///
  /// [candidatePeriods] must already be the canonical current + still-
  /// redeemable set derived from official redemption windows. A period is
  /// omitted only when both official domains are already validated/promoted;
  /// unchanged validated historical data is therefore reused locally.
  List<OfficialInvoiceAwardPeriod> missingPeriodsForManualRefresh({
    required Iterable<OfficialInvoiceAwardPeriod> candidatePeriods,
    required Set<OfficialInvoiceAwardPeriod> generalPromotedPeriods,
    required Set<OfficialInvoiceAwardPeriod> cloudExclusivePromotedPeriods,
  }) {
    final missing = candidatePeriods.where((period) {
      return !generalPromotedPeriods.contains(period) ||
          !cloudExclusivePromotedPeriods.contains(period);
    }).toList(growable: false);
    missing.sort((a, b) {
      final year = a.rocYear.compareTo(b.rocYear);
      return year != 0 ? year : a.startMonth.compareTo(b.startMonth);
    });
    return missing;
  }

  bool _publicationDue(DateTime nowLocal) {
    final month = nowLocal.month;
    if (month.isEven) return false;
    return !nowLocal.isBefore(DateTime(nowLocal.year, month, 25, 14));
  }

  bool get canCreateFormalTransaction => false;
}
