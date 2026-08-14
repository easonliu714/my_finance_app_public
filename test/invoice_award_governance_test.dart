import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_governance.dart';

void main() {
  const period = InvoiceAwardPeriod(
    id: '2026-01-02',
    year: 2026,
    monthStart: 1,
    monthEnd: 2,
  );

  const specialRule = InvoiceAwardNumberRule(
    id: 'special-12345678',
    periodId: '2026-01-02',
    number: '12345678',
    tier: InvoiceAwardPrizeTier.special,
  );

  const firstRule = InvoiceAwardNumberRule(
    id: 'first-87654321',
    periodId: '2026-01-02',
    number: '87654321',
    tier: InvoiceAwardPrizeTier.first,
  );

  test('award period contains configured months only', () {
    expect(period.containsMonth(1), isTrue);
    expect(period.containsMonth(2), isTrue);
    expect(period.containsMonth(3), isFalse);
  });

  test('full invoice number match returns matched result and keeps review-first behavior', () {
    const matcher = InvoiceAwardMatcher(rules: <InvoiceAwardNumberRule>[specialRule, firstRule]);
    const candidate = InvoiceAwardCandidate(
      id: 'manual-1',
      invoiceNumber: 'AB-12345678',
      periodId: '2026-01-02',
      sourceLabel: 'manual',
    );

    final result = matcher.match(candidate);

    expect(candidate.normalizedNumber, '12345678');
    expect(result.status, InvoiceAwardMatchStatus.matched);
    expect(result.tier, InvoiceAwardPrizeTier.special);
    expect(result.rule, specialRule);
    expect(result.needsReview, isTrue);
    expect(result.canCreateTransactionAutomatically, isFalse);
  });

  test('last three digits return partial sixth-tier review candidate', () {
    const matcher = InvoiceAwardMatcher(rules: <InvoiceAwardNumberRule>[firstRule]);
    const candidate = InvoiceAwardCandidate(
      id: 'qr-1',
      invoiceNumber: '11111321',
      periodId: '2026-01-02',
      sourceLabel: 'qr',
    );

    final result = matcher.match(candidate);

    expect(result.status, InvoiceAwardMatchStatus.partial);
    expect(result.tier, InvoiceAwardPrizeTier.sixth);
    expect(result.rule, firstRule);
    expect(result.needsReview, isTrue);
    expect(result.canCreateTransactionAutomatically, isFalse);
  });

  test('not matched invoice does not need award review', () {
    const matcher = InvoiceAwardMatcher(rules: <InvoiceAwardNumberRule>[specialRule]);
    const candidate = InvoiceAwardCandidate(
      id: 'ai-1',
      invoiceNumber: '00000000',
      periodId: '2026-01-02',
      sourceLabel: 'ai',
    );

    final result = matcher.match(candidate);

    expect(result.status, InvoiceAwardMatchStatus.notMatched);
    expect(result.tier, InvoiceAwardPrizeTier.none);
    expect(result.needsReview, isFalse);
    expect(result.canCreateTransactionAutomatically, isFalse);
  });

  test('invalid invoice number is reviewable and never creates transactions automatically', () {
    const matcher = InvoiceAwardMatcher(rules: <InvoiceAwardNumberRule>[specialRule]);
    const candidate = InvoiceAwardCandidate(
      id: 'invalid-1',
      invoiceNumber: 'ABC',
      periodId: '2026-01-02',
      sourceLabel: 'manual',
    );

    final result = matcher.match(candidate);

    expect(candidate.isValid, isFalse);
    expect(result.status, InvoiceAwardMatchStatus.invalid);
    expect(result.tier, InvoiceAwardPrizeTier.none);
    expect(result.needsReview, isTrue);
    expect(result.canCreateTransactionAutomatically, isFalse);
  });

  test('official portal link keeps credential custody out of app scope', () {
    const link = CloudInvoicePortalLink.ministryOfFinance;

    expect(link.title, '財政部電子發票整合服務平台');
    expect(link.officialUrl, 'https://www.einvoice.nat.gov.tw/');
    expect(link.description, contains('不在 App 內保管憑證'));
    expect(InvoiceAwardGovernanceCopy.noCredentialCustody, contains('不保管官方平台帳密'));
    expect(InvoiceAwardGovernanceCopy.reviewFirst, contains('不會自動建立交易'));
  });
}
