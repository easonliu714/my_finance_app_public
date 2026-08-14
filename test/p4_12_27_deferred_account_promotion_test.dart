import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_draft_promotion_service.dart';

void main() {
  test('account-required result is distinct from conflict and rejection', () {
    const summary = PrivateCloudInvoiceDraftPromotionSummary(
      results: <PrivateCloudInvoiceDraftPromotionResult>[
        PrivateCloudInvoiceDraftPromotionResult(
          draftId: 'draft-1',
          status: PrivateCloudInvoiceDraftPromotionStatus.accountRequired,
          message: 'ACCOUNT_REQUIRED_FOR_NEW_TRANSACTION',
        ),
      ],
    );

    expect(summary.accountRequiredCount, 1);
    expect(summary.conflictCount, 0);
    expect(summary.rejectedCount, 0);
  });

  test('P4.12.27 promotion compares before requiring account', () {
    final page = File(
      'lib/features/invoice/lab/private_cloud_invoice_draft_promotion_page.dart',
    ).readAsStringSync();
    final service = File(
      'lib/features/invoice/lab/private_cloud_invoice_draft_promotion_service.dart',
    ).readAsStringSync();

    expect(page, contains('付款帳戶（建立新交易時必填）'));
    expect(page, contains('批次付款帳戶（選填）'));
    expect(page, contains('比對並處理'));
    expect(service, contains('ACCOUNT_REQUIRED_FOR_NEW_TRANSACTION'));
    expect(service, contains('accountRequired'));
    expect(service, isNot(contains('AND t.account_name = ?')));
    expect(
      service.indexOf('final duplicates = await transaction.rawQuery'),
      lessThan(service.indexOf('final resolvedAccountId')),
    );
  });
}
