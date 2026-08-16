import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_local_completeness_policy.dart';

void main() {
  test('strict time parser accepts exact time without inventing seconds', () {
    expect(extractStrictInvoiceTime('交易時間 09:05'), '09:05');
    expect(extractStrictInvoiceTime('23：59：58'), '23:59:58');
  });
  test('strict time parser rejects invalid fuzzy and ambiguous evidence', () {
    expect(extractStrictInvoiceTime('24:00'), '');
    expect(extractStrictInvoiceTime('10:61'), '');
    expect(extractStrictInvoiceTime('O9:05'), '');
    expect(extractStrictInvoiceTime('09:05 10:06'), '');
  });
}
