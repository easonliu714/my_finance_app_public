import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_lkg_repository.dart';
import 'package:my_finance_app/features/invoice/invoice_award_official_dataset.dart';

void main() {
  const codec = OfficialInvoiceAwardLkgCodec();
  const validator = OfficialInvoiceAwardDatasetValidator();
  const period = OfficialInvoiceAwardPeriod(
    rocYear: 115,
    startMonth: 5,
    endMonth: 6,
  );

  OfficialInvoiceAwardDataset dataset(List<OfficialInvoiceAwardRule> rules) =>
      OfficialInvoiceAwardDataset(
        period: period,
        provenance: OfficialInvoiceAwardProvenance(
          sourceId: OfficialInvoiceAwardProvenance.ministryOfFinanceSourceId,
          fetchedAt: DateTime.utc(2026, 7, 25, 6),
          parserVersion: 'official-html-v1',
          contentSha256: 'A' * 64,
        ),
        rules: rules,
        published: true,
        complete: true,
      );

  const rules = <OfficialInvoiceAwardRule>[
    OfficialInvoiceAwardRule(
      kind: OfficialInvoiceAwardRuleKind.first,
      number: '83663333',
    ),
    OfficialInvoiceAwardRule(
      kind: OfficialInvoiceAwardRuleKind.special,
      number: '38548029',
    ),
    OfficialInvoiceAwardRule(
      kind: OfficialInvoiceAwardRuleKind.grand,
      number: '10138845',
    ),
  ];

  test('codec is deterministic across input rule order', () {
    final forward = codec.encode(dataset(rules), validator);
    final reverse = codec.encode(dataset(rules.reversed.toList()), validator);

    expect(forward.periodId, period.id);
    expect(forward.payload, reverse.payload);
    expect(forward.payload, contains('"schemaVersion":1'));
    expect(forward.payload, contains('"contentSha256":"${'a' * 64}"'));
  });

  test('round-trip preserves validated provenance and rules', () {
    final snapshot = codec.encode(dataset(rules), validator);
    final decoded = codec.decode(snapshot, validator);

    expect(decoded.period.id, period.id);
    expect(decoded.provenance.sourceId,
        OfficialInvoiceAwardProvenance.ministryOfFinanceSourceId);
    expect(decoded.provenance.contentSha256, 'a' * 64);
    expect(decoded.rules.length, rules.length);
    expect(validator.validate(decoded).isValid, isTrue);
  });

  test('encode refuses invalid dataset before persistence boundary', () {
    final invalid = OfficialInvoiceAwardDataset(
      period: period,
      provenance: OfficialInvoiceAwardProvenance(
        sourceId: 'third-party',
        fetchedAt: DateTime.utc(2026, 7, 25),
        parserVersion: 'bad',
        contentSha256: 'a' * 64,
      ),
      rules: rules,
      published: true,
      complete: true,
    );

    expect(() => codec.encode(invalid, validator), throwsFormatException);
  });

  test('decode fails closed when snapshot period key is inconsistent', () {
    final snapshot = codec.encode(dataset(rules), validator);
    final mismatched = OfficialInvoiceAwardLkgSnapshot(
      periodId: '115-03-04',
      payload: snapshot.payload,
    );

    expect(() => codec.decode(mismatched, validator), throwsFormatException);
  });
}
