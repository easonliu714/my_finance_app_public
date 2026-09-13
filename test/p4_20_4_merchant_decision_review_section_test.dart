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
    ValueChanged<InvoiceMerchantDecisionSelection>? onSelected,
    ValueChanged<InvoiceMerchantDecisionSelection>? onConfirmRecognitionBinding,
    ValueChanged<InvoiceMerchantDecisionSelection>? onConfirmOfficialBinding,
    bool sellerTaxIdAuthoritative = false,
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
            sellerTaxIdAuthoritative: sellerTaxIdAuthoritative,
            onSelected: onSelected ?? (_) {},
            onConfirmRecognitionBinding: onConfirmRecognitionBinding,
            onConfirmOfficialBinding: onConfirmOfficialBinding ?? (_) {},
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

  testWidgets('explicit tap emits exact resolved MerchantBrand selection snapshot',
      (tester) async {
    InvoiceMerchantDecisionSelection? captured;
    await tester.pumpWidget(
      buildSection(onSelected: (selection) => captured = selection),
    );

    final select = find.byKey(
      InvoiceMerchantDecisionComposerCard.selectKey(
        InvoiceMerchantDecisionOption.existingMerchantBrand,
      ),
    );
    await tester.ensureVisible(select);
    await tester.tap(select);
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured!.option, InvoiceMerchantDecisionOption.existingMerchantBrand);
    expect(captured!.displayName, 'OK Mart');
    expect(captured!.sellerTaxId, '31655572');
    expect(captured!.invoiceLiteral, 'OK超商 晶技門市');
    expect(captured!.requiresMerchantBindingConfirmation, isFalse);
    expect(captured!.writesFormalTransaction, isFalse);
  });

  testWidgets('recognition binding stays hidden without independent sellerTaxId authority',
      (tester) async {
    InvoiceMerchantDecisionSelection? confirmed;
    await tester.pumpWidget(
      buildSection(
        selectedOption: InvoiceMerchantDecisionOption.recognition,
        onConfirmRecognitionBinding: (selection) => confirmed = selection,
      ),
    );

    expect(
      find.byKey(InvoiceMerchantDecisionComposerCard.recognitionBindingConfirmKey),
      findsNothing,
    );
    expect(confirmed, isNull);
  });

  testWidgets('authoritative sellerTaxId exposes second recognition binding action only',
      (tester) async {
    InvoiceMerchantDecisionSelection? confirmed;
    await tester.pumpWidget(
      buildSection(
        selectedOption: InvoiceMerchantDecisionOption.recognition,
        sellerTaxIdAuthoritative: true,
        onConfirmRecognitionBinding: (selection) => confirmed = selection,
      ),
    );

    final confirmFinder = find.byKey(
      InvoiceMerchantDecisionComposerCard.recognitionBindingConfirmKey,
    );
    expect(confirmFinder, findsOneWidget);
    await tester.ensureVisible(confirmFinder);
    await tester.tap(confirmFinder);
    await tester.pump();

    expect(confirmed, isNotNull);
    expect(confirmed!.option, InvoiceMerchantDecisionOption.recognition);
    expect(confirmed!.displayName, 'OK超商 晶技門市');
    expect(confirmed!.sellerTaxId, '31655572');
    expect(confirmed!.invoiceLiteral, 'OK超商 晶技門市');
    expect(confirmed!.requiresMerchantBindingConfirmation, isTrue);
    expect(confirmed!.writesFormalTransaction, isFalse);
  });

  testWidgets('official lane requires second explicit action and emits exact binding snapshot',
      (tester) async {
    InvoiceMerchantDecisionSelection? selected;
    InvoiceMerchantDecisionSelection? confirmed;

    await tester.pumpWidget(
      buildSection(
        selectedOption: InvoiceMerchantDecisionOption.officialRegistry,
        onSelected: (selection) => selected = selection,
        onConfirmOfficialBinding: (selection) => confirmed = selection,
      ),
    );

    expect(selected, isNull);
    expect(
      find.byKey(InvoiceMerchantDecisionComposerCard.officialBindingConfirmKey),
      findsOneWidget,
    );

    final confirmFinder = find.byKey(
      InvoiceMerchantDecisionComposerCard.officialBindingConfirmKey,
    );
    await tester.ensureVisible(confirmFinder);
    await tester.tap(confirmFinder);
    await tester.pump();

    expect(confirmed, isNotNull);
    expect(confirmed!.option, InvoiceMerchantDecisionOption.officialRegistry);
    expect(confirmed!.displayName, '富達零售股份有限公司晶技門市');
    expect(confirmed!.sellerTaxId, '31655572');
    expect(confirmed!.invoiceLiteral, 'OK超商 晶技門市');
    expect(confirmed!.requiresMerchantBindingConfirmation, isTrue);
    expect(confirmed!.writesFormalTransaction, isFalse);
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
