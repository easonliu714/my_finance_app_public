import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_notification_policy.dart';

void main() {
  const policy = InvoiceAwardNotificationPolicy();

  test('opt-out due reminder is local navigation only', () {
    expect(
      policy.shouldPresentDueReminder(
        automaticRefreshConsented: false,
        notificationPermissionGranted: true,
        awardReminderEnabled: true,
        publicationDue: true,
        currentGeneralPromoted: false,
        currentCloudExclusivePromoted: false,
      ),
      isTrue,
    );
    expect(policy.reminderRoute, '/invoice/award-check');
    expect(policy.canFetchOfficialDataset, isFalse);
    expect(policy.canMatchInvoice, isFalse);
    expect(policy.canRedeemPrize, isFalse);
    expect(policy.canConfigureMofRemittance, isFalse);
    expect(policy.canCreateFormalTransaction, isFalse);
  });

  test('consent permission setting and due state all fail closed', () {
    bool decide({
      bool consent = false,
      bool permission = true,
      bool enabled = true,
      bool due = true,
      bool general = false,
      bool cloud = false,
    }) =>
        policy.shouldPresentDueReminder(
          automaticRefreshConsented: consent,
          notificationPermissionGranted: permission,
          awardReminderEnabled: enabled,
          publicationDue: due,
          currentGeneralPromoted: general,
          currentCloudExclusivePromoted: cloud,
        );

    expect(decide(consent: true), isFalse);
    expect(decide(permission: false), isFalse);
    expect(decide(enabled: false), isFalse);
    expect(decide(due: false), isFalse);
    expect(decide(general: true, cloud: true), isFalse);
    expect(decide(general: true, cloud: false), isTrue);
    expect(decide(general: false, cloud: true), isTrue);
  });
}
