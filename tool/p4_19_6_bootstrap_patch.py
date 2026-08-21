from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one match, got {count}: {old[:120]!r}')
    p.write_text(text.replace(old, new, 1))


# 1) Calculator is button-only: never request focus / IME from the expression box.
replace_once(
    'lib/features/product/product_review_calculator.dart',
    """            TextField(\n              key: const Key('product_review_calculator_expression'),\n              controller: _expression,\n              keyboardType: TextInputType.text,\n              decoration: const InputDecoration(\n                labelText: '算式',\n                hintText: '例如：(45 + 27) × 0.9',\n                border: OutlineInputBorder(),\n              ),\n              onChanged: (_) => _recalculate(silent: true),\n            ),""",
    """            TextField(\n              key: const Key('product_review_calculator_expression'),\n              controller: _expression,\n              readOnly: true,\n              canRequestFocus: false,\n              showCursor: false,\n              enableInteractiveSelection: false,\n              decoration: const InputDecoration(\n                labelText: '算式',\n                hintText: '請使用下方按鍵輸入算式',\n                border: OutlineInputBorder(),\n              ),\n            ),""",
)

# 2) Review card: default multi-product stays total-only, but explicit user restore
#    may opt into quantity × user-entered shared unit price. Restore is never disabled.
replace_once(
    'lib/features/product/product_manual_review_card.dart',
    "  bool _totalManualOverride = false;\n",
    "  bool _totalManualOverride = false;\n  bool _multiProductUserAutoMode = false;\n",
)
replace_once(
    'lib/features/product/product_manual_review_card.dart',
    "    _selectedAccount = null;\n\n    if (candidate.hasMultipleProducts) {",
    "    _selectedAccount = null;\n    _multiProductUserAutoMode = false;\n\n    if (candidate.hasMultipleProducts) {",
)
replace_once(
    'lib/features/product/product_manual_review_card.dart',
    "    final multiProduct = candidate.hasMultipleProducts;\n    final autoTotal = _calculatedTotal();",
    "    final multiProduct = candidate.hasMultipleProducts;\n    final multiProductAutoMode = multiProduct && _multiProductUserAutoMode;\n    final autoTotal = _calculatedTotal();",
)
replace_once(
    'lib/features/product/product_manual_review_card.dart',
    "              if (multiProduct) ...[",
    "              if (multiProduct && !multiProductAutoMode) ...[",
)
replace_once(
    'lib/features/product/product_manual_review_card.dart',
    """                        decoration: const InputDecoration(\n                          labelText: '數量',\n                          border: OutlineInputBorder(),\n                        ),""",
    """                        decoration: InputDecoration(\n                          labelText: multiProductAutoMode ? '合計數量' : '數量',\n                          helperText: multiProductAutoMode\n                              ? '已由您明確啟用自動計算；此數量會乘上您輸入的共同單價。'\n                              : null,\n                          border: const OutlineInputBorder(),\n                        ),""",
)
replace_once(
    'lib/features/product/product_manual_review_card.dart',
    """                        decoration: const InputDecoration(\n                          labelText: '單價',\n                          border: OutlineInputBorder(),\n                        ),""",
    """                        decoration: InputDecoration(\n                          labelText: multiProductAutoMode ? '共同單價（人工）' : '單價',\n                          helperText: multiProductAutoMode\n                              ? '只在您主動選擇此模式後使用；不是 AI 對多商品單價的推測。'\n                              : null,\n                          border: const OutlineInputBorder(),\n                        ),""",
)
replace_once(
    'lib/features/product/product_manual_review_card.dart',
    """                    multiProduct: multiProduct,\n                  ),""",
    """                    multiProduct: multiProduct,\n                    multiProductAutoMode: multiProductAutoMode,\n                  ),""",
)
replace_once(
    'lib/features/product/product_manual_review_card.dart',
    """                  if (!multiProduct)\n                    TextButton.icon(\n                      key: ProductManualReviewCard.restoreAutoTotalKey,\n                      onPressed:\n                          _calculatedTotal() == null ? null : _restoreAutoTotal,\n                      icon: const Icon(Icons.refresh_outlined),\n                      label: const Text('恢復自動計算'),\n                    ),""",
    """                  TextButton.icon(\n                    key: ProductManualReviewCard.restoreAutoTotalKey,\n                    onPressed: _restoreAutoTotal,\n                    icon: const Icon(Icons.refresh_outlined),\n                    label: const Text('恢復自動計算'),\n                  ),""",
)
replace_once(
    'lib/features/product/product_manual_review_card.dart',
    """  void _restoreAutoTotal() {\n    final total = _calculatedTotal();\n    if (total == null) return;\n    _invalidateConfirmedReview();\n    setState(() {\n      _totalManualOverride = false;\n      _totalAmount.text = _number(total);\n    });\n  }""",
    """  void _restoreAutoTotal() {\n    _invalidateConfirmedReview();\n    setState(() {\n      if (widget.candidate.hasMultipleProducts) {\n        _multiProductUserAutoMode = true;\n      }\n      _totalManualOverride = false;\n      final total = _calculatedTotal();\n      _totalAmount.text = total == null ? '' : _number(total);\n    });\n  }""",
)
replace_once(
    'lib/features/product/product_manual_review_card.dart',
    "    if (widget.candidate.hasMultipleProducts) return null;\n",
    "    if (widget.candidate.hasMultipleProducts && !_multiProductUserAutoMode) {\n      return null;\n    }\n",
)
replace_once(
    'lib/features/product/product_manual_review_card.dart',
    """  String _totalHelperText({\n    required double? autoTotal,\n    required double? aiTotal,\n    required bool multiProduct,\n  }) {\n    if (multiProduct) {""",
    """  String _totalHelperText({\n    required double? autoTotal,\n    required double? aiTotal,\n    required bool multiProduct,\n    required bool multiProductAutoMode,\n  }) {\n    if (multiProduct && !multiProductAutoMode) {""",
)
replace_once(
    'lib/features/product/product_manual_review_card.dart',
    """    if (autoTotal != null) {\n      final ai = aiTotal != null && aiTotal != autoTotal\n          ? '；AI 辨識總額 ${_number(aiTotal)}'\n          : '';\n      return '自動：數量 × 單價 = ${_number(autoTotal)}$ai';\n    }\n    return aiTotal == null\n        ? '請輸入數量與單價，或直接人工輸入總額。'\n        : 'AI 辨識總額：${_number(aiTotal)}';""",
    """    if (autoTotal != null) {\n      final ai = aiTotal != null && aiTotal != autoTotal\n          ? '；AI 辨識總額 ${_number(aiTotal)}'\n          : '';\n      final prefix = multiProductAutoMode\n          ? '使用者啟用自動：合計數量 × 共同單價'\n          : '自動：數量 × 單價';\n      return '$prefix = ${_number(autoTotal)}$ai';\n    }\n    if (multiProductAutoMode) {\n      return '自動計算已啟用；請輸入合計數量與共同單價。';\n    }\n    return aiTotal == null\n        ? '請輸入數量與單價，或直接人工輸入總額。'\n        : 'AI 辨識總額：${_number(aiTotal)}';""",
)
replace_once(
    'lib/features/product/product_manual_review_card.dart',
    "    final unitPrice = multiProduct ? null : _parse(_unitPrice.text);\n",
    "    final unitPrice = multiProduct && !_multiProductUserAutoMode\n        ? null\n        : _parse(_unitPrice.text);\n",
)
replace_once(
    'lib/features/product/product_manual_review_card.dart',
    """    noteParts.add(\n      multiProduct\n          ? '總額來源：多商品人工覆核'\n          : _totalManualOverride\n              ? '總額來源：人工修改'\n              : '總額來源：數量×單價自動計算',\n    );""",
    """    noteParts.add(\n      multiProduct && !_multiProductUserAutoMode\n          ? '總額來源：多商品人工覆核'\n          : _totalManualOverride\n              ? '總額來源：人工修改'\n              : multiProduct\n                  ? '總額來源：多商品人工指定共同單價×合計數量自動計算'\n                  : '總額來源：數量×單價自動計算',\n    );""",
)
replace_once(
    'lib/features/product/product_manual_review_card.dart',
    """      totalMode: multiProduct || _totalManualOverride\n          ? ProductReviewTotalMode.manualOverride\n          : ProductReviewTotalMode.automatic,""",
    """      totalMode: (multiProduct && !_multiProductUserAutoMode) ||\n              _totalManualOverride\n          ? ProductReviewTotalMode.manualOverride\n          : ProductReviewTotalMode.automatic,""",
)

# 3) Existing P4.19.5 calculator interaction gate must use only the on-screen keypad.
replace_once(
    'test/p4_19_5_product_review_ux_test.dart',
    """    await tester.enterText(\n      find.byKey(const Key('product_review_calculator_expression')),\n      '(45 + 27) × 0.9',\n    );\n    await tester.pump();\n    expect(find.text('結果：64.8'), findsOneWidget);""",
    """    final expressionFinder =\n        find.byKey(const Key('product_review_calculator_expression'));\n    final expressionField = tester.widget<TextField>(expressionFinder);\n    expect(expressionField.readOnly, isTrue);\n    expect(expressionField.canRequestFocus, isFalse);\n\n    await tester.tap(find.widgetWithText(OutlinedButton, 'C'));\n    await tester.pump();\n    for (final keyText in <String>[\n      '(', '4', '5', '+', '2', '7', ')', '×', '0', '.', '9',\n    ]) {\n      await tester.tap(find.widgetWithText(OutlinedButton, keyText));\n      await tester.pump();\n    }\n    expect(find.text('結果：64.8'), findsOneWidget);""",
)

# 4) Version authority.
for path in [
    'pubspec.yaml',
    'lib/features/invoice/lab/private_cloud_invoice_lab_config.dart',
    'test/p4_12_34_1_version_contract_test.dart',
    'test/p4_12_38_exact_head_test.dart',
]:
    replace_once(path, '4.19.5+442', '4.19.6+443')

# 5) Focused P4.19.6 regression suite.
Path('test/p4_19_6_product_review_ux_hotfix_test.dart').write_text(r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/product_manual_review_card.dart';
import 'package:my_finance_app/features/product/product_recognition_candidate.dart';
import 'package:my_finance_app/features/product/product_review_calculator.dart';
import 'package:my_finance_app/features/product/product_transaction_handoff.dart';

void main() {
  testWidgets('calculator expression is button-only and never requests IME focus',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showProductReviewCalculator(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('product_review_calculator_expression')),
    );
    expect(field.readOnly, isTrue);
    expect(field.canRequestFocus, isFalse);
    expect(field.enableInteractiveSelection, isFalse);

    await tester.tap(find.widgetWithText(OutlinedButton, '4'));
    await tester.tap(find.widgetWithText(OutlinedButton, '+'));
    await tester.tap(find.widgetWithText(OutlinedButton, '5'));
    await tester.pump();
    expect(find.text('結果：9'), findsOneWidget);
  });

  testWidgets('restore auto is enabled even before quantity and unit price are valid',
      (tester) async {
    const candidate = ProductRecognitionCandidate(
      productName: '飲料',
      totalAmount: 17,
      categorySuggestion: '飲料水果',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProductManualReviewCard(
              candidate: candidate,
              categoryOptions: const <String>['飲料水果'],
              merchantOptions: const <String>['不使用商家'],
              accountOptions: const <String>['一卡通'],
              onReviewed: (_) {},
            ),
          ),
        ),
      ),
    );

    final restoreFinder = find.byKey(ProductManualReviewCard.restoreAutoTotalKey);
    final restoreButton = tester.widget<TextButton>(restoreFinder);
    expect(restoreButton.onPressed, isNotNull);

    await tester.ensureVisible(restoreFinder);
    await tester.tap(restoreFinder);
    await tester.pump();

    var totalField = tester.widget<TextFormField>(
      find.byKey(ProductManualReviewCard.totalAmountFieldKey),
    );
    expect(totalField.controller?.text, '');

    await tester.enterText(
      find.byKey(ProductManualReviewCard.quantityFieldKey),
      '2',
    );
    await tester.enterText(
      find.byKey(ProductManualReviewCard.unitPriceFieldKey),
      '20',
    );
    await tester.pump();

    totalField = tester.widget<TextFormField>(
      find.byKey(ProductManualReviewCard.totalAmountFieldKey),
    );
    expect(totalField.controller?.text, '40');
  });

  testWidgets('multi-product explicit restore may use user-entered shared unit price',
      (tester) async {
    ProductTransactionDraftSeed? reviewed;
    const candidate = ProductRecognitionCandidate(
      productName: '飲料、點心',
      quantity: 2,
      totalAmount: 72,
      categorySuggestion: '飲料水果',
      merchantName: 'OK便利商店',
      warnings: <String>['multiple_products_visible'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProductManualReviewCard(
              candidate: candidate,
              categoryOptions: const <String>['飲料水果'],
              merchantOptions: const <String>['不使用商家', 'OK便利商店'],
              accountOptions: const <String>['一卡通'],
              onReviewed: (value) => reviewed = value,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(ProductManualReviewCard.unitPriceFieldKey), findsNothing);
    final restoreFinder = find.byKey(ProductManualReviewCard.restoreAutoTotalKey);
    expect(tester.widget<TextButton>(restoreFinder).onPressed, isNotNull);

    await tester.ensureVisible(restoreFinder);
    await tester.tap(restoreFinder);
    await tester.pump();

    expect(find.byKey(ProductManualReviewCard.unitPriceFieldKey), findsOneWidget);
    expect(find.text('共同單價（人工）'), findsOneWidget);

    await tester.enterText(
      find.byKey(ProductManualReviewCard.unitPriceFieldKey),
      '30',
    );
    await tester.pump();

    final totalField = tester.widget<TextFormField>(
      find.byKey(ProductManualReviewCard.totalAmountFieldKey),
    );
    expect(totalField.controller?.text, '60');

    final account = find.byKey(ProductManualReviewCard.accountFieldKey);
    await tester.ensureVisible(account);
    await tester.tap(account);
    await tester.pumpAndSettle();
    await tester.tap(find.text('一卡通').last);
    await tester.pumpAndSettle();

    final confirm = find.byKey(ProductManualReviewCard.confirmKey);
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(reviewed?.quantity, 2);
    expect(reviewed?.unitPrice, 30);
    expect(reviewed?.amount, 60);
    expect(reviewed?.totalMode, ProductReviewTotalMode.automatic);
    expect(reviewed?.note, contains('人工指定共同單價'));
  });
}
''')

# 6) P4.19.6 signed canary cloned from the proven P4.19.5 chain.
src = Path('.github/workflows/p4_19_5_signed_canary.yml').read_text()
workflow = src
workflow = workflow.replace('P4.19.5', 'P4.19.6')
workflow = workflow.replace('p4_19_5', 'p4_19_6')
workflow = workflow.replace('p4-19-5', 'p4-19-6')
workflow = workflow.replace('4.19.5+442', '4.19.6+443')
workflow = workflow.replace("4.19.5'", "4.19.6'")
workflow = workflow.replace("'442'", "'443'")
workflow = workflow.replace('--build-number=442', '--build-number=443')
workflow = workflow.replace(
    "github.head_ref == 'p4-19-6-product-review-ux-and-voice-roadmap'",
    "github.head_ref == 'p4-19-6-calculator-ime-auto-total'",
)
workflow = workflow.replace(
    'Frozen P4.19.4 real-device ancestry gate',
    'Frozen P4.19.5 real-device ancestry gate',
)
workflow = workflow.replace(
    "frozen='cc32bcad3187e2e9c725bc9efd2b929d7bd803ff'",
    "frozen='dc6ffee4acdf90869f95c7cfcc529cb717156f23'",
)
workflow = workflow.replace(
    'P4.19.4 real-device PASS ancestor: PASS',
    'P4.19.5 real-device PASS ancestor: PASS',
)
workflow = workflow.replace(
    'Focused P4.19.6 product-review UX gates',
    'Focused P4.19.6 calculator/auto-total UX gates',
)
workflow = workflow.replace(
    'flutter test test/p4_19_6_product_review_ux_test.dart',
    'flutter test test/p4_19_6_product_review_ux_hotfix_test.dart\n          flutter test test/p4_19_5_product_review_ux_test.dart',
)
workflow = workflow.replace(
    "            printf 'CALCULATOR_REVIEW_INVALIDATION=PASS\\n'",
    "            printf 'CALCULATOR_REVIEW_INVALIDATION=PASS\\n'\n            printf 'CALCULATOR_IME_SUPPRESSED=PASS\\n'\n            printf 'RESTORE_AUTO_ALWAYS_ENABLED=PASS\\n'\n            printf 'MULTI_PRODUCT_USER_AUTO_OPT_IN=PASS\\n'",
)
Path('.github/workflows/p4_19_6_signed_canary.yml').write_text(workflow)

print('P4.19.6 bootstrap patch complete')
