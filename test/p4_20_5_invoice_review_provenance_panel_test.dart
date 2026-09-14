import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_decision_composer.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_decision_review_section.dart';
import 'package:my_finance_app/features/merchant/merchant_identity_provenance_report_service.dart';
import 'package:my_finance_app/features/merchant/merchant_identity_repository.dart';

class _FakeProvenanceReportService
    extends MerchantIdentityProvenanceReportService {
  _FakeProvenanceReportService(this.report);

  final MerchantIdentityProvenanceReport report;
  int readCount = 0;
  String? lastSellerTaxId;

  @override
  Future<MerchantIdentityProvenanceReport> buildForSellerIdentifier(
    String sellerIdentifier,
  ) async {
    readCount += 1;
    lastSellerTaxId = sellerIdentifier;
    return report;
  }
}

void main() {
  MerchantIdentityProvenanceReport reportFor(String sellerTaxId) {
    return MerchantIdentityProvenanceReport(
      sellerIdentifier: sellerTaxId,
      currentIdentity: ConfirmedMerchantIdentity(
        merchantBrandId: 'brand-ok',
        displayName: 'OK Mart',
        sellerIdentifier: sellerTaxId,
        legalEntityId: 'legal-ok',
        legalName: '來來超商股份有限公司',
        registrySource: 'gcis-company',
        registryVersion: 'registry-v2',
      ),
      bindingHistory: <MerchantIdentityBindingPeriod>[
        MerchantIdentityBindingPeriod(
          id: 'binding-a',
          merchantBrandId: 'brand-old',
          sellerIdentifier: sellerTaxId,
          evidenceSource: 'explicit_user_confirmation',
          effectiveFrom: DateTime.utc(2026, 9, 1),
          effectiveTo: DateTime.utc(2026, 9, 10),
        ),
        MerchantIdentityBindingPeriod(
          id: 'binding-b',
          merchantBrandId: 'brand-ok',
          sellerIdentifier: sellerTaxId,
          evidenceSource: 'explicit_user_confirmation',
          effectiveFrom: DateTime.utc(2026, 9, 10),
        ),
      ],
      legalNameHistory: const [],
      branchOutletHistory: const [],
    );
  }

  Widget buildSection({
    required String sellerTaxId,
    required MerchantIdentityProvenanceReportService service,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: InvoiceMerchantDecisionReviewSection(
            recognizedMerchantName: 'OK超商 晶技門市',
            sellerTaxId: sellerTaxId,
            recognitionSourceLabel: 'OCR',
            identityContext: null,
            selectedOption: null,
            sellerTaxIdAuthoritative: false,
            provenanceReportService: service,
            onSelected: (_) {},
            onConfirmOfficialBinding: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets(
    'exact sellerTaxId exposes read-only merchant identity provenance without changing authority',
    (tester) async {
      final service = _FakeProvenanceReportService(reportFor('31655572'));

      await tester.pumpWidget(
        buildSection(sellerTaxId: '31655572', service: service),
      );
      await tester.pumpAndSettle();

      expect(service.readCount, 1);
      expect(service.lastSellerTaxId, '31655572');
      expect(
        find.byKey(InvoiceMerchantDecisionReviewSection.provenancePanelKey),
        findsOneWidget,
      );
      expect(find.text('商家身分歷史與來源'), findsOneWidget);
      expect(find.text('目前 MerchantBrand：OK Mart'), findsOneWidget);

      await tester.tap(find.text('商家身分歷史與來源'));
      await tester.pumpAndSettle();

      expect(find.text('MerchantBrand 綁定歷史：2 筆'), findsOneWidget);
      expect(find.text('官方法定名稱歷史：0 筆'), findsOneWidget);
      expect(find.text('分店／營業據點歷史：0 筆'), findsOneWidget);
      expect(find.textContaining('explicit_user_confirmation'), findsNWidgets(2));
      expect(
        find.textContaining('不會因 Registry 命中或辨識結果自動升格'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'non-exact sellerTaxId does not mount or query provenance panel',
    (tester) async {
      final service = _FakeProvenanceReportService(reportFor('31655572'));

      await tester.pumpWidget(
        buildSection(sellerTaxId: 'OCR-3165', service: service),
      );
      await tester.pumpAndSettle();

      expect(service.readCount, 0);
      expect(
        find.byKey(InvoiceMerchantDecisionReviewSection.provenancePanelKey),
        findsNothing,
      );
      expect(find.text('商家身分歷史與來源'), findsNothing);
    },
  );

  testWidgets(
    'provenance panel does not expose merchant binding or formal-save actions',
    (tester) async {
      final service = _FakeProvenanceReportService(reportFor('31655572'));

      await tester.pumpWidget(
        buildSection(sellerTaxId: '31655572', service: service),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('商家身分歷史與來源'));
      await tester.pumpAndSettle();

      expect(find.text('確認建立／綁定'), findsNothing);
      expect(find.text('儲存'), findsNothing);
      expect(find.text('Save'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
    },
  );
}
