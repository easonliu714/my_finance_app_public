import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_official_dataset.dart';

void main() {
  const validator = OfficialInvoiceAwardDatasetValidator();
  const period = OfficialInvoiceAwardPeriod(rocYear: 115, startMonth: 5, endMonth: 6);

  OfficialInvoiceAwardDataset dataset({
    String sourceId = OfficialInvoiceAwardProvenance.ministryOfFinanceSourceId,
    bool published = true,
    bool complete = true,
  }) {
    return OfficialInvoiceAwardDataset(
      period: period,
      provenance: OfficialInvoiceAwardProvenance(
        sourceId: sourceId,
        fetchedAt: DateTime.utc(2026, 7, 25),
        parserVersion: 'official-html-v1',
        contentSha256: 'a' * 64,
      ),
      published: published,
      complete: complete,
      rules: const [
        OfficialInvoiceAwardRule(kind: OfficialInvoiceAwardRuleKind.special, number: '38548029'),
        OfficialInvoiceAwardRule(kind: OfficialInvoiceAwardRuleKind.grand, number: '10138845'),
        OfficialInvoiceAwardRule(kind: OfficialInvoiceAwardRuleKind.first, number: '24121106'),
        OfficialInvoiceAwardRule(kind: OfficialInvoiceAwardRuleKind.first, number: '28589937'),
        OfficialInvoiceAwardRule(kind: OfficialInvoiceAwardRuleKind.first, number: '83663333'),
        OfficialInvoiceAwardRule(kind: OfficialInvoiceAwardRuleKind.additionalSixth, number: '614'),
        OfficialInvoiceAwardRule(kind: OfficialInvoiceAwardRuleKind.cloudExclusive, number: '12345678'),
      ],
    );
  }

  test('official complete dataset validates with immutable provenance', () {
    expect(validator.validate(dataset()).isValid, isTrue);
  });

  test('non-official, unpublished, or incomplete dataset fails closed', () {
    expect(validator.validate(dataset(sourceId: 'third-party')).isValid, isFalse);
    expect(validator.validate(dataset(published: false)).isValid, isFalse);
    expect(validator.validate(dataset(complete: false)).isValid, isFalse);
  });

  test('general first-prize suffix rules are deterministic, not generic rule suffixes', () {
    const matcher = OfficialInvoiceAwardMatcher(validator: validator);
    final result = matcher.match(
      dataset: dataset(),
      candidate: const OfficialInvoiceAwardCandidate(
        invoiceNumber: '99121106',
        period: period,
        cloudExclusiveEligible: false,
      ),
    );
    expect(result.kind, OfficialInvoiceAwardMatchKind.sixth);
    expect(result.canCreateFormalTransaction, isFalse);
  });

  test('special award does not degrade into suffix matching', () {
    const matcher = OfficialInvoiceAwardMatcher(validator: validator);
    final result = matcher.match(
      dataset: dataset(),
      candidate: const OfficialInvoiceAwardCandidate(
        invoiceNumber: '99048029',
        period: period,
        cloudExclusiveEligible: false,
      ),
    );
    expect(result.kind, OfficialInvoiceAwardMatchKind.notMatched);
  });

  test('cloud-exclusive rule requires explicit authoritative eligibility', () {
    const matcher = OfficialInvoiceAwardMatcher(validator: validator);
    final ineligible = matcher.match(
      dataset: dataset(),
      candidate: const OfficialInvoiceAwardCandidate(
        invoiceNumber: '12345678',
        period: period,
        cloudExclusiveEligible: false,
      ),
    );
    final eligible = matcher.match(
      dataset: dataset(),
      candidate: const OfficialInvoiceAwardCandidate(
        invoiceNumber: '12345678',
        period: period,
        cloudExclusiveEligible: true,
      ),
    );
    expect(ineligible.kind, OfficialInvoiceAwardMatchKind.notMatched);
    expect(eligible.kind, OfficialInvoiceAwardMatchKind.cloudExclusive);
  });

  test('period mismatch fails closed', () {
    const matcher = OfficialInvoiceAwardMatcher(validator: validator);
    final result = matcher.match(
      dataset: dataset(),
      candidate: const OfficialInvoiceAwardCandidate(
        invoiceNumber: '38548029',
        period: OfficialInvoiceAwardPeriod(rocYear: 115, startMonth: 3, endMonth: 4),
        cloudExclusiveEligible: false,
      ),
    );
    expect(result.kind, OfficialInvoiceAwardMatchKind.invalid);
  });
}
