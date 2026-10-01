import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/app_build_metadata.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_lab_config.dart';

void main() {
  test('Issue #13 release metadata is authorized as 4.20.17+475', () {
    expect(AppBuildMetadata.appVersion, '4.20.17+475');
    expect(
      AppBuildMetadata.phase,
      'issue-13-cloud500-pdfium-lifecycle-safe-475',
    );
    expect(PrivateCloudInvoiceLabConfig.validationVersion, '4.20.17+475');
  });
}
