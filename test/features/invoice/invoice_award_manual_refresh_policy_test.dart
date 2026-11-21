import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_manual_refresh_policy.dart';
import 'package:my_finance_app/features/invoice/invoice_award_official_dataset.dart';

void main() {
  const janFeb = OfficialInvoiceAwardPeriod(
    rocYear: 115,
    startMonth: 1,
    endMonth: 2,
  );
  const marApr = OfficialInvoiceAwardPeriod(
    rocYear: 115,
    startMonth: 3,
    endMonth: 4,
  );
  const mayJun = OfficialInvoiceAwardPeriod(
    rocYear: 115,
    startMonth: 5,
    endMonth: 6,
  );

  group('InvoiceAwardManualRefreshPolicy', () {
    test('opt-out is a hard zero-background-network boundary', () {
      const policy = InvoiceAwardManualRefreshPolicy(
        automaticRefreshConsented: false,
      );

      expect(policy.permitsBackgroundAwardNetworkFetch, isFalse);
      expect(policy.canCreateFormalTransaction, isFalse);
    });

    test('local reminder starts at 14:00 on odd-month 25th only', () {
      const policy = InvoiceAwardManualRefreshPolicy(
        automaticRefreshConsented: false,
      );

      bool due(DateTime now) => policy.shouldSurfaceLocalReminder(
            nowLocal: now,
            notificationPermissionGranted: true,
            awardReminderEnabled: true,
            currentGeneralPromoted: false,
            currentCloudExclusivePromoted: false,
          );

      expect(due(DateTime(2026, 9, 25, 13, 59)), isFalse);
      expect(due(DateTime(2026, 9, 25, 14, 0)), isTrue);
      expect(due(DateTime(2026, 10, 25, 14, 0)), isFalse);
    });

    test('reminder is suppressed by consent, settings, or completed promotion', () {
      const optedOut = InvoiceAwardManualRefreshPolicy(
        automaticRefreshConsented: false,
      );
      const consented = InvoiceAwardManualRefreshPolicy(
        automaticRefreshConsented: true,
      );
      final due = DateTime(2026, 9, 25, 14, 0);

      expect(
        consented.shouldSurfaceLocalReminder(
          nowLocal: due,
          notificationPermissionGranted: true,
          awardReminderEnabled: true,
          currentGeneralPromoted: false,
          currentCloudExclusivePromoted: false,
        ),
        isFalse,
      );
      expect(
        optedOut.shouldSurfaceLocalReminder(
          nowLocal: due,
          notificationPermissionGranted: false,
          awardReminderEnabled: true,
          currentGeneralPromoted: false,
          currentCloudExclusivePromoted: false,
        ),
        isFalse,
      );
      expect(
        optedOut.shouldSurfaceLocalReminder(
          nowLocal: due,
          notificationPermissionGranted: true,
          awardReminderEnabled: false,
          currentGeneralPromoted: false,
          currentCloudExclusivePromoted: false,
        ),
        isFalse,
      );
      expect(
        optedOut.shouldSurfaceLocalReminder(
          nowLocal: due,
          notificationPermissionGranted: true,
          awardReminderEnabled: true,
          currentGeneralPromoted: true,
          currentCloudExclusivePromoted: true,
        ),
        isFalse,
      );
    });

    test('manual refresh requests current/redeemable periods missing either domain', () {
      const policy = InvoiceAwardManualRefreshPolicy(
        automaticRefreshConsented: false,
      );

      final missing = policy.missingPeriodsForManualRefresh(
        candidatePeriods: const [mayJun, janFeb, marApr],
        generalPromotedPeriods: const {janFeb, marApr},
        cloudExclusivePromotedPeriods: const {janFeb, mayJun},
      );

      expect(missing, const [marApr, mayJun]);
    });
  });
}
