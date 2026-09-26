import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_check_presentation.dart';
import 'package:my_finance_app/features/invoice/invoice_award_match_projection.dart';

void main() {
  group('InvoiceAwardCheckPresentation', () {
    const builder = InvoiceAwardCheckPresentationBuilder();

    test('renders official window, gross prize and review warnings read-only', () {
      final projection = InvoiceAwardMatchProjection(
        periodId: '115-09-10',
        domain: InvoiceAwardProjectionDomain.cloudExclusive,
        tierLabel: '雲端發票專屬獎 800 元',
        grossAmount: 800,
        redemptionStart: DateTime.utc(2026, 12, 6),
        redemptionEnd: DateTime.utc(2027, 3, 5),
        officialDatasetFingerprint: 'a' * 64,
        parserRuleVersion: 'issue13-v1',
        eligibilityWarning: '雲端資格尚待確認',
        exclusionWarnings: const <String>['已逾兌領期限時不得主張可兌領'],
      );

      final presentation = builder.build(projection);
      expect(presentation, isNotNull);
      expect(presentation!.periodId, '115-09-10');
      expect(presentation.grossAmount, 800);
      expect(presentation.redemptionStart, DateTime.utc(2026, 12, 6));
      expect(presentation.redemptionEnd, DateTime.utc(2027, 3, 5));
      expect(presentation.reviewRequired, isTrue);
      expect(presentation.warnings, contains('雲端資格尚待確認'));
      expect(presentation.canRedeemOrClaim, isFalse);
      expect(presentation.canConfigureAutomaticRemittance, isFalse);
      expect(presentation.canCreateFormalTransaction, isFalse);
      expect(
        InvoiceAwardCheckPresentation.redemptionDisclosure,
        contains('不是兌獎或領獎平台'),
      );
      expect(
        InvoiceAwardCheckPresentation.remittanceDisclosure,
        contains('不會設定或執行財政部自動匯款'),
      );
    });

    test('fails closed when match provenance is invalid', () {
      final invalid = InvoiceAwardMatchProjection(
        periodId: '',
        domain: InvoiceAwardProjectionDomain.general,
        tierLabel: '六獎',
        grossAmount: 200,
        redemptionStart: DateTime.utc(2026, 12, 6),
        redemptionEnd: DateTime.utc(2027, 3, 5),
        officialDatasetFingerprint: '',
        parserRuleVersion: 'issue13-v1',
        eligibilityWarning: null,
        exclusionWarnings: const <String>[],
      );
      expect(builder.build(invalid), isNull);
    });
  });
}
