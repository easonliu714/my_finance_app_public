import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_match_projection.dart';

void main() {
  const builder = InvoiceAwardMatchProjectionBuilder();

  test('builds read-only projection with official provenance', () {
    final projection = builder.build(
      periodId: '115-07-08',
      domain: InvoiceAwardProjectionDomain.general,
      tierLabel: '特別獎',
      grossAmount: 10000000,
      redemptionStart: DateTime.utc(2026, 10, 6),
      redemptionEnd: DateTime.utc(2027, 1, 5),
      officialDatasetFingerprint: 'sha256:general-fixture',
      parserRuleVersion: 'issue13-v1',
    );

    expect(projection, isNotNull);
    expect(projection!.requiresReview, isFalse);
    expect(projection.canCreateFormalTransaction, isFalse);
    expect(projection.canRedeemOrClaim, isFalse);
    expect(projection.canConfigureAutomaticRemittance, isFalse);
  });

  test('fails closed when provenance or redemption bounds are ambiguous', () {
    expect(
      builder.build(
        periodId: '115-07-08',
        domain: InvoiceAwardProjectionDomain.general,
        tierLabel: '特別獎',
        grossAmount: 10000000,
        redemptionStart: DateTime.utc(2026, 10, 6),
        redemptionEnd: DateTime.utc(2027, 1, 5),
        officialDatasetFingerprint: '',
        parserRuleVersion: 'issue13-v1',
      ),
      isNull,
    );

    expect(
      builder.build(
        periodId: '115-07-08',
        domain: InvoiceAwardProjectionDomain.general,
        tierLabel: '特別獎',
        grossAmount: 10000000,
        redemptionStart: DateTime.utc(2027, 1, 6),
        redemptionEnd: DateTime.utc(2027, 1, 5),
        officialDatasetFingerprint: 'sha256:general-fixture',
        parserRuleVersion: 'issue13-v1',
      ),
      isNull,
    );
  });

  test('surfaces cloud eligibility and exclusion warnings for review', () {
    final projection = builder.build(
      periodId: '115-07-08',
      domain: InvoiceAwardProjectionDomain.cloudExclusive,
      tierLabel: '雲端發票專屬獎 800 元',
      grossAmount: 800,
      redemptionStart: DateTime.utc(2026, 10, 6),
      redemptionEnd: DateTime.utc(2027, 1, 5),
      officialDatasetFingerprint: 'sha256:cloud-fixture',
      parserRuleVersion: 'issue13-v1',
      eligibilityWarning: '雲端資格待確認',
      exclusionWarnings: const <String>['發票狀態需人工確認'],
    );

    expect(projection, isNotNull);
    expect(projection!.requiresReview, isTrue);
    expect(projection.exclusionWarnings, hasLength(1));
    expect(projection.canCreateFormalTransaction, isFalse);
  });
}
