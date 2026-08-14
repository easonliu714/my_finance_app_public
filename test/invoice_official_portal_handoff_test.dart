import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_external_source_consent.dart';
import 'package:my_finance_app/features/invoice/invoice_official_portal_handoff.dart';

void main() {
  const readyConsent = InvoiceExternalSourceConsent(
    networkAccessAcknowledged: true,
    externalDataAcknowledged: true,
    reviewGateAcknowledged: true,
    revokeDeleteAcknowledged: true,
  );

  test('handoff requires completed external-source consent gates', () {
    const service = InvoiceOfficialPortalHandoffService();
    const blockedConsent = InvoiceExternalSourceConsent(
      networkAccessAcknowledged: false,
      externalDataAcknowledged: true,
      reviewGateAcknowledged: true,
      revokeDeleteAcknowledged: true,
    );

    expect(
      () => service.createRequest(
        id: 'handoff-1',
        consent: blockedConsent,
        target: InvoiceOfficialPortalHandoffTarget(
          name: 'Official portal',
          uri: Uri.parse('https://example.com/invoice'),
        ),
      ),
      throwsA(isA<InvoiceOfficialPortalHandoffError>()),
    );
  });

  test('handoff target must use HTTPS', () {
    const service = InvoiceOfficialPortalHandoffService();

    expect(
      () => service.createRequest(
        id: 'handoff-1',
        consent: readyConsent,
        target: InvoiceOfficialPortalHandoffTarget(
          name: 'Unsafe portal',
          uri: Uri.parse('http://example.com/invoice'),
        ),
      ),
      throwsA(isA<InvoiceOfficialPortalHandoffError>()),
    );
  });

  test('handoff is user initiated and never stores credentials or starts background sync', () {
    final service = InvoiceOfficialPortalHandoffService(clock: () => DateTime.utc(2026, 6, 10, 8));

    final request = service.createRequest(
      id: 'handoff-1',
      consent: readyConsent,
      target: InvoiceOfficialPortalHandoffTarget(
        name: 'Official portal',
        uri: Uri.parse('https://example.com/invoice'),
      ),
    );

    expect(request.id, 'handoff-1');
    expect(request.leavesApp, isTrue);
    expect(request.storesCredential, isFalse);
    expect(request.startsBackgroundSync, isFalse);
    expect(request.createsDraftOrTransactionAutomatically, isFalse);
    expect(request.createdAt, DateTime.utc(2026, 6, 10, 8));
  });

  test('required disclosure documents no credential custody, no background sync, and review gate', () {
    expect(InvoiceOfficialPortalHandoffCopy.requiredDisclosure, contains(InvoiceOfficialPortalHandoffCopy.noCredentialCustody));
    expect(InvoiceOfficialPortalHandoffCopy.requiredDisclosure, contains(InvoiceOfficialPortalHandoffCopy.noBackgroundSync));
    expect(InvoiceOfficialPortalHandoffCopy.requiredDisclosure, contains(InvoiceOfficialPortalHandoffCopy.reviewRequired));
  });
}
