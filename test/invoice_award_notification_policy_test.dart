import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_notification_policy.dart';

void main() {
  const policy = InvoiceAwardNotificationPolicy();

  test('opt-out due period can issue local Award Check reminder', () {
    final decision = policy.decide(
      automaticRefreshConsented: false,
      notificationPermissionGranted: true,
      localReminderEnabled: true,
      awardRefreshDue: true,
      currentGeneralDatasetValidated: false,
      currentCloudDatasetValidated: false,
    );

    expect(decision, InvoiceAwardNotificationDecision.remindToOpenAwardCheck);
    expect(decision.mayFetchAwardNumbers, isFalse);
    expect(decision.mayCreateFormalTransaction, isFalse);
    expect(decision.mayConfigureMofRemittance, isFalse);
  });

  test('no reminder without permission or local setting', () {
    for (final permission in [false, true]) {
      for (final enabled in [false, true]) {
        if (permission && enabled) continue;
        expect(
          policy.decide(
            automaticRefreshConsented: false,
            notificationPermissionGranted: permission,
            localReminderEnabled: enabled,
            awardRefreshDue: true,
            currentGeneralDatasetValidated: false,
            currentCloudDatasetValidated: false,
          ),
          InvoiceAwardNotificationDecision.none,
        );
      }
    }
  });

  test('automatic-refresh consent suppresses manual-refresh reminder', () {
    expect(
      policy.decide(
        automaticRefreshConsented: true,
        notificationPermissionGranted: true,
        localReminderEnabled: true,
        awardRefreshDue: true,
        currentGeneralDatasetValidated: false,
        currentCloudDatasetValidated: false,
      ),
      InvoiceAwardNotificationDecision.none,
    );
  });

  test('validated current general and cloud datasets suppress reminder', () {
    expect(
      policy.decide(
        automaticRefreshConsented: false,
        notificationPermissionGranted: true,
        localReminderEnabled: true,
        awardRefreshDue: true,
        currentGeneralDatasetValidated: true,
        currentCloudDatasetValidated: true,
      ),
      InvoiceAwardNotificationDecision.none,
    );
  });

  test('not-due state suppresses reminder', () {
    expect(
      policy.decide(
        automaticRefreshConsented: false,
        notificationPermissionGranted: true,
        localReminderEnabled: true,
        awardRefreshDue: false,
        currentGeneralDatasetValidated: false,
        currentCloudDatasetValidated: false,
      ),
      InvoiceAwardNotificationDecision.none,
    );
  });
}
