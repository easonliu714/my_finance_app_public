import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_decision_composer.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_decision_composer_card.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_decision_review_section.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_identity_review_service.dart';
import 'package:my_finance_app/features/merchant/business_registry_repository.dart';
import 'package:my_finance_app/features/merchant/merchant_identity_resolution_policy.dart';

void main() {
  const context = InvoiceMerchantIdentityReviewContext(
    decision: MerchantIdentityResolutionDecision(
      literalMerchantText: 'OK超商 晶技門市',
      sellerIdentifier: '31655572',
      registryLookupAllowed: true,
      officialLegalNameSuggestion: '富達零售股份有限公司晶技門市',
      formalMerchantName: 'OK Mart',
      requiresBrandConfirmation: false,
      reason: MerchantIdentityResolutionReason.confirmedBrandLink,
    ),
    registryStatus: BusinessRegistryLookupStatus.hit,
    registryVersion: 'p4.20.3-fia-2026-09-09-b98874df3998',
    registryCoverage: '全台公司／商業／分公司',
    registrySourceDataDate: '2026-09-09',
  );

  Widget buildSection({
    String sellerTaxId = '31655572',
    InvoiceMerchantDecisionOption? selectedOption,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: InvoiceMerchantDecisionReviewSection(
            recognizedMerchantName: 'OK超商 晶技門市',
            sellerTaxId: sellerTaxId,
            recognitionSourceLabel: 'QR + OCR',
            identityContext: context,
            selectedOption: selectedOption,
            onSelected: (_) {},
            onConfirmOfficialBinding: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('mountable section exposes all three lanes with no implicit selection',
      (tester) async {
    await tester.pumpWidget(buildSection());

    expect(find.byKey(InvoiceMerchantDecisionReviewSection.sectionKey), findsOneWidget);
    expect(find.byKey(InvoiceMerchantDecisionComposerCard.recognitionLaneKey), findsOneWidget);
    expect(find.byKey(InvoiceMerchantDecisionComposerCard.existingMerchantLaneKey), findsOneWidget);
    expect(find.byKey(InvoiceMerchantDecisionComposerCard.officialRegistryLaneKey), findsOneWidget);
    expect(find.text('OK超商 晶技門市'), findsOneWidget);
    expect(find.text('OK Mart'), findsOneWidget);
    expect(find.text('富達零售股份有限公司晶技門市'), findsOneWidget);
    expect(find.text('已明確選擇'), findsNothing);
    expect(find.byKey(InvoiceMerchantDecisionComposerCard.officialBindingConfirmKey), findsNothing);
  });

  testWidgets('stale sellerTaxId context fails closed even when parent carries old selection',
      (tester) async {
    await tester.pumpWidget(
      buildSection(
        sellerTaxId: '60282181',
        selectedOption: InvoiceMerchantDecisionOption.officialRegistry,
      ),
    );

    expect(find.text('舊官方法定名稱'), findsNothing);
    expect(find.text('富達零售股份有限公司晶技門市'), findsNothing);
    expect(find.text('OK Mart'), findsNothing);
    expect(find.text('已明確選擇'), findsNothing);
    expect(find.byKey(InvoiceMerchantDecisionComposerCard.officialBindingConfirmKey), findsNothing);

    final officialSelect = tester.widget<OutlinedButton>(
      find.byKey(
        InvoiceMerchantDecisionComposerCard.selectKey(
          InvoiceMerchantDecisionOption.officialRegistry,
        ),
      ),
    );
    expect(officialSelect.onPressed, isNull);
  });
}
