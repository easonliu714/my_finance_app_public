import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/app_build_metadata.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_lab_config.dart';

void main() {
  test('P4.20.5 release metadata is frozen to 4.20.5+462', () {
    expect(AppBuildMetadata.appVersion, '4.20.5+462');
    expect(
      AppBuildMetadata.phase,
      'P4.20.5-merchant-identity-history-learning-462',
    );
    expect(PrivateCloudInvoiceLabConfig.validationVersion, '4.20.5+462');
  });
}
