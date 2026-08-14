import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_mock_provider.dart';

void main() {
  test('valid minimal scenario returns pending review-first candidate', () {
    final provider = CloudInvoiceMockProvider(clock: () => DateTime.utc(2026, 6, 10, 8));

    final result = provider.fetch(CloudInvoiceMockScenario.validMinimal);

    expect(result.isSuccess, isTrue);
    expect(result.hasCandidates, isTrue);
    expect(result.candidates.single.status, CloudInvoiceCandidateStatus.pending);
    expect(result.candidates.single.requiresUserReview, isTrue);
    expect(result.candidates.single.canCreateFormalTransactionAutomatically, isFalse);
    expect(result.candidates.single.fetchedAt, DateTime.utc(2026, 6, 10, 8));
  });

  test('valid with items scenario preserves line items', () {
    const provider = CloudInvoiceMockProvider();

    final result = provider.fetch(CloudInvoiceMockScenario.validWithItems);

    expect(result.isSuccess, isTrue);
    expect(result.candidates.single.hasLineItems, isTrue);
    expect(result.candidates.single.lineItems, hasLength(2));
    expect(result.candidates.single.lineItems.first.hasCategorySuggestion, isTrue);
  });

  test('partial payload scenario stays pending with warnings', () {
    const provider = CloudInvoiceMockProvider();

    final result = provider.fetch(CloudInvoiceMockScenario.partialPayload);

    expect(result.isSuccess, isTrue);
    expect(result.candidates.single.status, CloudInvoiceCandidateStatus.pending);
    expect(result.candidates.single.hasWarnings, isTrue);
    expect(result.candidates.single.displaySellerName, '未命名雲端發票商家');
  });

  test('malformed payload scenario returns rejected candidate', () {
    const provider = CloudInvoiceMockProvider();

    final result = provider.fetch(CloudInvoiceMockScenario.malformedPayload);

    expect(result.isSuccess, isTrue);
    expect(result.candidates.single.status, CloudInvoiceCandidateStatus.rejected);
    expect(result.candidates.single.errorCategory, CloudInvoiceCandidateErrorCategory.parseError);
    expect(result.candidates.single.canCreateFormalTransactionAutomatically, isFalse);
  });

  test('duplicate scenario returns duplicate candidate requiring user review', () {
    const provider = CloudInvoiceMockProvider();

    final result = provider.fetch(CloudInvoiceMockScenario.duplicateInvoice);

    expect(result.isSuccess, isTrue);
    expect(result.candidates.single.status, CloudInvoiceCandidateStatus.duplicate);
    expect(result.candidates.single.requiresUserReview, isTrue);
    expect(result.candidates.single.duplicateKey, 'AB12345678|2026-06-09|120|12345678');
  });

  test('authorization failures do not produce candidates or retry loops', () {
    const provider = CloudInvoiceMockProvider();

    final unauthorized = provider.fetch(CloudInvoiceMockScenario.unauthorized);
    final expired = provider.fetch(CloudInvoiceMockScenario.expiredAuthorization);

    expect(unauthorized.isSuccess, isFalse);
    expect(unauthorized.errorCategory, CloudInvoiceCandidateErrorCategory.authorization);
    expect(unauthorized.hasCandidates, isFalse);
    expect(unauthorized.canScheduleBackgroundRetry, isFalse);
    expect(expired.errorCategory, CloudInvoiceCandidateErrorCategory.authorization);
  });

  test('retryable failures allow manual retry only', () {
    const provider = CloudInvoiceMockProvider();

    final network = provider.fetch(CloudInvoiceMockScenario.networkUnavailable);
    final rateLimited = provider.fetch(CloudInvoiceMockScenario.rateLimited);

    expect(network.isSuccess, isFalse);
    expect(network.canRetryManually, isTrue);
    expect(network.canScheduleBackgroundRetry, isFalse);
    expect(rateLimited.errorCategory, CloudInvoiceCandidateErrorCategory.rateLimited);
    expect(rateLimited.canRetryManually, isTrue);
  });

  test('unsupported carrier failure is safe and non retryable', () {
    const provider = CloudInvoiceMockProvider();

    final result = provider.fetch(CloudInvoiceMockScenario.unsupportedCarrier);

    expect(result.isSuccess, isFalse);
    expect(result.errorCategory, CloudInvoiceCandidateErrorCategory.unsupportedCarrier);
    expect(result.canRetryManually, isFalse);
    expect(result.hasCandidates, isFalse);
  });
}
