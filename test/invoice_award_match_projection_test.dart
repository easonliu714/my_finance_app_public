import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_match_projection.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud500_production_policy.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;

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

  test('Owner C blocks legacy cloud-500 prize projections in release', () {
    bool blocked({
      required bool release,
      required bool cloud,
      required int amount,
      required String label,
    }) =>
        Cloud500ProductionPolicy.blocksCloud500PrizeProjectionForBuild(
          isReleaseBuild: release,
          isCloudExclusive: cloud,
          grossAmount: amount,
          tierLabel: label,
        );

    expect(blocked(release: true, cloud: true, amount: 500,
        label: '雲端發票專屬獎 500 元'), isTrue);
    expect(blocked(release: true, cloud: true, amount: 800,
        label: 'cloud-500'), isTrue);
    expect(blocked(release: true, cloud: true, amount: 800,
        label: '雲端發票專屬獎 800 元'), isFalse);
    expect(blocked(release: true, cloud: false, amount: 500,
        label: '一般發票 500 元'), isFalse);
    expect(blocked(release: false, cloud: true, amount: 500,
        label: '雲端發票專屬獎 500 元'), isFalse);

    // Direct constructors must use the same build-mode authority guard.
    final legacy = InvoiceAwardMatchProjection(
      periodId: '115-07-08',
      domain: InvoiceAwardProjectionDomain.cloudExclusive,
      tierLabel: '雲端發票專屬獎 500 元',
      grossAmount: 500,
      redemptionStart: DateTime.utc(2026, 10, 6),
      redemptionEnd: DateTime.utc(2027, 1, 5),
      officialDatasetFingerprint: 'sha256:legacy-cloud500',
      parserRuleVersion: 'legacy',
      eligibilityWarning: null,
      exclusionWarnings: const <String>[],
    );
    expect(legacy.hasValidProvenance, !kReleaseMode);
  });
}
