import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_item_detail_parser.dart';

void main() {
  const parser = InvoiceItemDetailParser();
  const detailPrefix = InvoiceItemDetailParser.expectedPrefix;

  test('parse returns item suggestions from detail fixture', () {
    final result = parser.parse('$detailPrefix冰美式咖啡:1:55:茶葉蛋:2:13');

    expect(result.isValid, isTrue);
    expect(result.requiresReview, isFalse);
    expect(result.items, hasLength(2));

    expect(result.items.first.name, '冰美式咖啡');
    expect(result.items.first.quantity, 1);
    expect(result.items.first.unitPrice, 55);
    expect(result.items.first.amount, 55);

    expect(result.items.last.name, '茶葉蛋');
    expect(result.items.last.quantity, 2);
    expect(result.items.last.unitPrice, 13);
    expect(result.items.last.amount, 26);
  });

  test('parse keeps complete item groups and warns about trailing fields', () {
    final result = parser.parse('$detailPrefix冰美式咖啡:1:55:孤立欄位');

    expect(result.isValid, isTrue);
    expect(result.requiresReview, isTrue);
    expect(result.items, hasLength(1));
    expect(result.warningSummary, contains('TRAILING_FIELDS_IGNORED'));
  });

  test('parse blocks invalid or empty detail payloads', () {
    final notExpectedPrefix = parser.parse('AB12345678');
    final emptyItems = parser.parse(detailPrefix);
    final malformedItems = parser.parse('$detailPrefix冰美式咖啡:x:55');

    expect(notExpectedPrefix.isBlocked, isTrue);
    expect(notExpectedPrefix.errorSummary, contains('UNEXPECTED_PREFIX'));

    expect(emptyItems.isBlocked, isTrue);
    expect(emptyItems.errorSummary, contains('EMPTY_ITEMS'));

    expect(malformedItems.isBlocked, isTrue);
    expect(malformedItems.errorSummary, contains('NO_USABLE_ITEMS'));
    expect(malformedItems.warningSummary, contains('BAD_QUANTITY_SKIPPED'));
  });

  test('parse converts parsed items into cloud invoice line item suggestions', () {
    final result = parser.parse('$detailPrefix冰美式咖啡:1:55:茶葉蛋:2:13');
    final items = result.toCloudInvoiceLineItems();

    expect(items, hasLength(2));

    expect(items.first.name, '冰美式咖啡');
    expect(items.first.quantity, 1);
    expect(items.first.unitPrice, 55);
    expect(items.first.amount, 55);

    expect(items.last.name, '茶葉蛋');
    expect(items.last.quantity, 2);
    expect(items.last.unitPrice, 13);
    expect(items.last.amount, 26);
  });

  test('invalid result cannot be converted into line item suggestions', () {
    final result = parser.parse('bad');

    expect(
      result.toCloudInvoiceLineItems,
      throwsA(isA<StateError>()),
    );
  });
}
