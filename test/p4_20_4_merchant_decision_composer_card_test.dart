import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_decision_composer.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_decision_composer_card.dart';

void main() {
  const composer = InvoiceMerchantDecisionComposer();

  InvoiceMerchantDecisionComposerState state() => composer.compose(
        const InvoiceMerchantDecisionInput(
          recognizedMerchantName: 'OK mart 晶技門市',
          sellerTaxId: '31655572',
          recognitionSourceLabel: 'QR',
          existingMerchantBrand: 'OK mart',
          officialLegalName: '富達零售股份有限公司晶技門市',
          officialEntityLabel: '分公司',
          officialParentSellerTaxId: '22853565',
          officialSource: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
          officialDataDate: '2026-09-09',
        ),
      );

  Future<void> pumpCard(
    WidgetTester tester, {
    required InvoiceMerchantDecisionComposerState value,
    required ValueChanged<InvoiceMerchantDecisionOption> onSelected,
    required ValueChanged<InvoiceMerchantDecisionSelection> onBind,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InvoiceMerchantDecisionComposerCard(
              state: value,
              onSelected: onSelected,
              onConfirmOfficialBinding: onBind,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders three distinct lanes without implicit selection',
      (tester) async {
    var selectionCalls = 0;
    var bindCalls = 0;

    await pumpCard(
      tester,
      value: state(),
      onSelected: (_) => selectionCalls += 1,
      onBind: (_) => bindCalls += 1,
    );

    expect(find.text('此次辨識結果'), findsOneWidget);
    expect(find.text('既有正式商家'), findsOneWidget);
    expect(find.text('官方登記資料'), findsOneWidget);
    expect(find.text('OK mart 晶技門市'), findsOneWidget);
    expect(find.text('OK mart'), findsOneWidget);
    expect(find.text('富達零售股份有限公司晶技門市'), findsOneWidget);
    expect(find.textContaining('MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY'),
        findsOneWidget);
    expect(find.textContaining('總機構 22853565'), findsOneWidget);
    expect(selectionCalls, 0);
    expect(bindCalls, 0);
    expect(find.byKey(InvoiceMerchantDecisionComposerCard.officialBindingConfirmKey),
        findsNothing);
  });

  testWidgets('official selection requires a second explicit binding action',
      (tester) async {
    var current = state();
    var bindingCalls = 0;

    await pumpCard(
      tester,
      value: current,
      onSelected: (_) {},
      onBind: (_) => bindingCalls += 1,
    );

    expect(find.byKey(InvoiceMerchantDecisionComposerCard.officialBindingConfirmKey),
        findsNothing);

    current = current.select(InvoiceMerchantDecisionOption.officialRegistry);
    await pumpCard(
      tester,
      value: current,
      onSelected: (_) {},
      onBind: (selection) {
        bindingCalls += 1;
        expect(selection.option, InvoiceMerchantDecisionOption.officialRegistry);
        expect(selection.invoiceLiteral, 'OK mart 晶技門市');
        expect(selection.writesFormalTransaction, isFalse);
      },
    );

    expect(find.text('已明確選擇'), findsOneWidget);
    expect(find.byKey(InvoiceMerchantDecisionComposerCard.officialBindingConfirmKey),
        findsOneWidget);
    expect(bindingCalls, 0);

    await tester.tap(
      find.byKey(InvoiceMerchantDecisionComposerCard.officialBindingConfirmKey),
    );
    await tester.pump();
    expect(bindingCalls, 1);
  });

  testWidgets('unavailable official lane fails closed', (tester) async {
    final unavailable = composer.compose(
      const InvoiceMerchantDecisionInput(
        recognizedMerchantName: '未登記商家原文',
        sellerTaxId: '12345678',
        recognitionSourceLabel: 'OCR',
        existingMerchantBrand: '使用者既有商家',
      ),
    );
    var officialSelected = false;

    await pumpCard(
      tester,
      value: unavailable,
      onSelected: (option) {
        if (option == InvoiceMerchantDecisionOption.officialRegistry) {
          officialSelected = true;
        }
      },
      onBind: (_) {},
    );

    final button = tester.widget<OutlinedButton>(
      find.byKey(
        InvoiceMerchantDecisionComposerCard.selectKey(
          InvoiceMerchantDecisionOption.officialRegistry,
        ),
      ),
    );
    expect(button.onPressed, isNull);
    expect(officialSelected, isFalse);
    expect(find.text('目前無可用候選'), findsOneWidget);
  });
}
