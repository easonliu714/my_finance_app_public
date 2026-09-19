import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/app_build_metadata.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_lab_config.dart';

void main() {
  test('Issue #29 successor release metadata is frozen to 4.20.5+463', () {
    expect(AppBuildMetadata.appVersion, '4.20.5+463');
    expect(
      AppBuildMetadata.phase,
      'issue-29-localized-multi-item-review-calculator-463',
    );
    expect(PrivateCloudInvoiceLabConfig.validationVersion, '4.20.5+463');
  });
}
