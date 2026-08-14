import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_qr_parser.dart';

void main() {
  const parser = InvoiceQrParser();

  test('empty QR payload returns a safe parse error', () {
    final result = parser.parse('  ');

    expect(result.isValid, isFalse);
    expect(result.errors, contains('QR payload 不可為空'));
  });

  test('lowercase invoice prefix is normalized before validation', () {
    final result = parser.parse(_leftQrPayload(invoiceNumber: 'ab12345678'));

    expect(result.errors, isEmpty);
    expect(result.invoiceNumber, 'AB12345678');
  });

  test('invalid ROC date returns parse error without throwing', () {
    final result = parser.parse(_leftQrPayload(dateText: '1151309'));

    expect(result.isValid, isFalse);
    expect(result.errors, contains('發票日期格式無法解析'));
  });

  test('invalid amount field returns parse error without throwing', () {
    final result = parser.parse(_leftQrPayload(salesAmountText: '--------'));

    expect(result.isValid, isFalse);
    expect(result.errors, contains('銷售額無法解析'));
  });

  test('blank seller identifier falls back to unnamed QR merchant label', () {
    final result = parser.parse(_leftQrPayload(invoiceNumber: 'CD87654321', sellerIdentifier: '        '));
    final item = result.toStagingItemCandidate(id: 'stage-blank-seller');

    expect(result.errors, isEmpty);
    expect(item.sellerName, '未命名 QR 商家');
  });
}

String _leftQrPayload({
  String invoiceNumber = 'AB12345678',
  String dateText = '1150609',
  String randomCode = '1234',
  String salesAmountText = '00000064',
  String totalAmountText = '00000078',
  String buyerIdentifier = '00000000',
  String sellerIdentifier = '24531234',
  String encryptedCheck = 'abcdefghijklmnopqrstuvwx',
}) {
  return '$invoiceNumber$dateText$randomCode$salesAmountText$totalAmountText$buyerIdentifier$sellerIdentifier$encryptedCheck';
}
