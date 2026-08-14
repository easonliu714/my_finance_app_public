import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_lab_config.dart';

void main() {
  test('package and validation versions stay aligned', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 4.17.2+422'));
    expect(PrivateCloudInvoiceLabConfig.validationVersion, '4.17.2+422');
  });
}
