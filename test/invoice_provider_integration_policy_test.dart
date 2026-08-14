import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_provider_integration_policy.dart';

void main() {
  const service = InvoiceProviderIntegrationPolicyService();

  test('official portal handoff and explicit user imports are allowed behind review gate', () {
    final portal = service.evaluate(InvoiceProviderIntegrationMode.officialPortalHandoff);
    final fileImport = service.evaluate(InvoiceProviderIntegrationMode.userImportedFile);
    final copiedImport = service.evaluate(InvoiceProviderIntegrationMode.copiedDataImport);

    for (final result in [portal, fileImport, copiedImport]) {
      expect(result.isAllowed, isTrue);
      expect(result.requiresReviewGate, isTrue);
      expect(result.allowsCredentialCustody, isFalse);
      expect(result.allowsBackgroundSync, isFalse);
      expect(result.allowsAutomaticTransactionCreation, isFalse);
    }
  });

  test('stored credentials and long-lived tokens are blocked by default', () {
    final storedCredential = service.evaluate(InvoiceProviderIntegrationMode.storedCredential);
    final longLivedToken = service.evaluate(InvoiceProviderIntegrationMode.longLivedToken);

    for (final result in [storedCredential, longLivedToken]) {
      expect(result.isBlocked, isTrue);
      expect(result.allowsCredentialCustody, isFalse);
      expect(result.reason, InvoiceProviderIntegrationPolicyCopy.credentialCustodyBlocked);
    }
  });

  test('background sync is blocked by default', () {
    final result = service.evaluate(InvoiceProviderIntegrationMode.backgroundSync);

    expect(result.isBlocked, isTrue);
    expect(result.allowsBackgroundSync, isFalse);
    expect(result.reason, InvoiceProviderIntegrationPolicyCopy.backgroundSyncBlocked);
  });

  test('embedded webview login is blocked by default', () {
    final result = service.evaluate(InvoiceProviderIntegrationMode.embeddedWebViewLogin);

    expect(result.isBlocked, isTrue);
    expect(result.allowsCredentialCustody, isFalse);
    expect(result.reason, InvoiceProviderIntegrationPolicyCopy.embeddedLoginBlocked);
  });

  test('session-only authorization requires future security review', () {
    final result = service.evaluate(InvoiceProviderIntegrationMode.sessionOnlyAuthorization);

    expect(result.requiresFutureReview, isTrue);
    expect(result.allowsCredentialCustody, isFalse);
    expect(result.allowsBackgroundSync, isFalse);
    expect(result.allowsAutomaticTransactionCreation, isFalse);
  });

  test('all integration modes have explicit policy decisions', () {
    final results = service.evaluateAll();

    expect(results, hasLength(InvoiceProviderIntegrationMode.values.length));
    expect(results.map((result) => result.mode).toSet(), InvoiceProviderIntegrationMode.values.toSet());
    expect(InvoiceProviderIntegrationPolicyCopy.defaultGuardrails, contains(InvoiceProviderIntegrationPolicyCopy.credentialCustodyBlocked));
    expect(InvoiceProviderIntegrationPolicyCopy.defaultGuardrails, contains(InvoiceProviderIntegrationPolicyCopy.backgroundSyncBlocked));
    expect(InvoiceProviderIntegrationPolicyCopy.defaultGuardrails, contains(InvoiceProviderIntegrationPolicyCopy.reviewGateRequired));
  });
}
