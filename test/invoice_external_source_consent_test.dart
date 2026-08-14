import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_external_source_consent.dart';

void main() {
  test('consent is not ready when required gates are missing', () {
    const consent = InvoiceExternalSourceConsent(
      networkAccessAcknowledged: false,
      externalDataAcknowledged: false,
      reviewGateAcknowledged: false,
      revokeDeleteAcknowledged: false,
    );

    expect(consent.isReady, isFalse);
    expect(consent.leavesDevice, isFalse);
    expect(consent.storesCredential, isFalse);
    expect(consent.missingGateMessages(), contains(InvoiceExternalSourceConsentCopy.networkGate));
    expect(consent.missingGateMessages(), contains(InvoiceExternalSourceConsentCopy.externalDataGate));
    expect(consent.missingGateMessages(), contains(InvoiceExternalSourceConsentCopy.reviewGate));
    expect(consent.missingGateMessages(), contains(InvoiceExternalSourceConsentCopy.revokeDeleteGate));
  });

  test('consent is ready when required gates are acknowledged and no secret is kept', () {
    const consent = InvoiceExternalSourceConsent(
      networkAccessAcknowledged: true,
      externalDataAcknowledged: true,
      reviewGateAcknowledged: true,
      revokeDeleteAcknowledged: true,
    );

    expect(consent.isReady, isTrue);
    expect(consent.leavesDevice, isTrue);
    expect(consent.storesCredential, isFalse);
    expect(consent.missingGateMessages(), isEmpty);
  });

  test('secret custody blocks readiness by default policy', () {
    const consent = InvoiceExternalSourceConsent(
      networkAccessAcknowledged: true,
      externalDataAcknowledged: true,
      reviewGateAcknowledged: true,
      revokeDeleteAcknowledged: true,
      credentialCustody: InvoiceExternalSourceCredentialCustody.encryptedToken,
    );

    expect(consent.isReady, isFalse);
    expect(consent.storesCredential, isTrue);
    expect(consent.missingGateMessages(), contains(InvoiceExternalSourceConsentCopy.credentialCustodyBlockedGate));
  });

  test('background sync requires sync frequency acknowledgement', () {
    const consent = InvoiceExternalSourceConsent(
      networkAccessAcknowledged: true,
      externalDataAcknowledged: true,
      reviewGateAcknowledged: true,
      revokeDeleteAcknowledged: true,
      backgroundSyncEnabled: true,
    );

    expect(consent.isReady, isFalse);
    expect(consent.missingGateMessages(), contains(InvoiceExternalSourceConsentCopy.syncFrequencyGate));
  });

  test('required disclosure includes data leaves device and review gate copy', () {
    expect(InvoiceExternalSourceConsentCopy.requiredDisclosure, contains(InvoiceExternalSourceConsentCopy.networkGate));
    expect(InvoiceExternalSourceConsentCopy.requiredDisclosure, contains(InvoiceExternalSourceConsentCopy.reviewGate));
    expect(InvoiceExternalSourceConsentCopy.requiredDisclosure, contains(InvoiceExternalSourceConsentCopy.credentialCustodyBlockedGate));
  });
}
