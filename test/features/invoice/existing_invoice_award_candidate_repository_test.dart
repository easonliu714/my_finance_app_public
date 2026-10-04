import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/existing_invoice_award_candidate_repository.dart';

void main() {
  group('GovernedInvoiceReviewNoteParser', () {
    test('accepts exact InvoiceTransactionHandoffContract note', () {
      final parsed = GovernedInvoiceReviewNoteParser.parse('''
來源：發票辨識人工覆核
發票號碼：AB12345678
賣方統編：12345678
發票期別：115/08
隨機碼：1234
品項明細：
- 咖啡：100
'''.trim());

      expect(parsed, isNotNull);
      expect(parsed!.invoiceNumber, 'AB12345678');
      expect(parsed.invoicePeriod, '115/08');
    });

    test('rejects arbitrary user note even when it contains invoice-like text', () {
      expect(
        GovernedInvoiceReviewNoteParser.parse(
          '聚餐，發票號碼：AB12345678，請記得對獎',
        ),
        isNull,
      );
    });

    test('rejects wrong source marker', () {
      expect(
        GovernedInvoiceReviewNoteParser.parse('''
來源：手動輸入
發票號碼：AB12345678
'''.trim()),
        isNull,
      );
    });

    test('rejects duplicate governed labels as ambiguous', () {
      expect(
        GovernedInvoiceReviewNoteParser.parse('''
來源：發票辨識人工覆核
發票號碼：AB12345678
發票號碼：CD87654321
'''.trim()),
        isNull,
      );
    });

    test('rejects unknown labels before line-item section', () {
      expect(
        GovernedInvoiceReviewNoteParser.parse('''
來源：發票辨識人工覆核
發票號碼：AB12345678
自行猜測：是
'''.trim()),
        isNull,
      );
    });

    test('rejects malformed invoice identity', () {
      expect(
        GovernedInvoiceReviewNoteParser.parse('''
來源：發票辨識人工覆核
發票號碼：12345678
'''.trim()),
        isNull,
      );
    });
  });
}
