import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_category_suggestion_service.dart';

void main() {
  test('time based fallback suggests breakfast lunch and dinner', () {
    const service = OfficialInvoiceCategorySuggestionService();

    expect(_suggest(service, id: 'breakfast', hour: 8).category, '早餐');
    expect(_suggest(service, id: 'lunch', hour: 12).category, '午餐');
    expect(_suggest(service, id: 'dinner', hour: 19).category, '晚餐');
  });

  test('time fallback remains review-only outside meal windows', () {
    const service = OfficialInvoiceCategorySuggestionService();
    final suggestion = _suggest(service, id: 'other', hour: 15);

    expect(suggestion.category, '午餐');
    expect(suggestion.confidence, lessThan(0.65));
    expect(suggestion.canPrefill, isFalse);
  });

  test('seller and line item evidence can suggest non meal category', () {
    const service = OfficialInvoiceCategorySuggestionService();
    final suggestion = service.suggestWithoutHistory(
      OfficialInvoiceCategorySuggestionInput(
        id: 'digital',
        invoiceDate: DateTime(2026, 6, 26, 15),
        sellerIdentifier: '',
        sellerName: '3C 電子商城',
        lineItems: const <CloudInvoiceLineItem>[
          CloudInvoiceLineItem(name: 'USB-C 充電器', amount: 1000),
        ],
      ),
    );

    expect(suggestion.category, '電子數碼');
    expect(suggestion.canPrefill, isTrue);
  });

  test('low confidence evidence remains unselected', () {
    const service = OfficialInvoiceCategorySuggestionService();
    final suggestion = service.suggestWithoutHistory(
      OfficialInvoiceCategorySuggestionInput(
        id: 'unknown',
        invoiceDate: DateTime(2026, 6, 26, 15),
        sellerIdentifier: '',
        sellerName: '某股份有限公司',
        lineItems: const <CloudInvoiceLineItem>[
          CloudInvoiceLineItem(name: '商品A', amount: 100),
        ],
      ),
    );

    expect(suggestion.category, isNull);
    expect(suggestion.canPrefill, isFalse);
  });

  test('history and UI contracts remain explainable editable and prefilled', () {
    final serviceSource = File(
      'lib/features/invoice/lab/official_invoice_category_suggestion_service.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/invoice/lab/private_cloud_invoice_draft_promotion_page.dart',
    ).readAsStringSync();

    expect(serviceSource, contains('cloud_invoice_metadata_links'));
    expect(serviceSource, contains('JOIN transactions'));
    expect(serviceSource, contains('historyEvidenceCount'));
    expect(serviceSource, contains('近期歷史紀錄權重較高'));
    expect(page, contains('智慧建議：'));
    expect(page, contains('suggestion.canPrefill'));
    expect(page, contains('return suggestion.category!'));
    expect(page, contains('_defaultCategoryFor(draft)'));
    expect(page, contains('付款帳戶（建立新交易時必填）'));
    expect(page, contains('_accountReviewDropdown(draft)'));
    expect(page, contains('_bulkAccountDropdown()'));
    expect(page, contains('待指定帳戶'));
  });
}

OfficialInvoiceCategorySuggestion _suggest(
  OfficialInvoiceCategorySuggestionService service, {
  required String id,
  required int hour,
  int minute = 0,
}) {
  return service.suggestWithoutHistory(
    OfficialInvoiceCategorySuggestionInput(
      id: id,
      invoiceDate: DateTime(2026, 6, 26, hour, minute),
      sellerIdentifier: '',
      sellerName: '便當店',
      lineItems: const <CloudInvoiceLineItem>[
        CloudInvoiceLineItem(name: '雞腿便當', amount: 120),
      ],
    ),
  );
}
