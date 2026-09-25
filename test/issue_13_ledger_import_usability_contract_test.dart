import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ledger views load the complete transaction history instead of 50 rows', () {
    final providers = File(
      'lib/features/transaction/transaction_providers.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/features/transaction/transaction_repository.dart',
    ).readAsStringSync();

    expect(providers, contains('listRecent(limit: 0)'));
    expect(repository, contains('limit: limit > 0 ? limit : null'));
  });

  test('report rows use the same compact summary policy as dashboard rows', () {
    final report = File(
      'lib/features/dashboard/ledger_detail_page.dart',
    ).readAsStringSync();

    expect(report, contains("final subtitleParts = <String>[time, accountText, record.memberName]"));
    expect(report, contains("merchant != '不使用商家'"));
    expect(report, contains('maxLines: 2'));
    expect(report, contains('overflow: TextOverflow.ellipsis'));
    expect(
      report,
      isNot(
        contains(
          "record.merchantName}\${record.note.isEmpty ? '' : ' · \${record.note}'}",
        ),
      ),
    );
  });

  test('official import surfaces excluded invoice and promotion reason evidence', () {
    final review = File(
      'lib/features/invoice/lab/official_invoice_detail_enrichment_review_page.dart',
    ).readAsStringSync();
    final preflight = File(
      'lib/features/invoice/lab/official_invoice_detail_draft_import_page.dart',
    ).readAsStringSync();
    final promotion = File(
      'lib/features/invoice/lab/private_cloud_invoice_draft_promotion_page.dart',
    ).readAsStringSync();

    expect(review, contains('目前不可進入正式交易的項目'));
    expect(review, contains('officialInvoiceDetailFailureLabel'));
    expect(preflight, contains('目前不可導入正式交易'));
    expect(preflight, contains('snapshot.rejectedItems'));
    expect(promotion, contains('未完成原因'));
    expect(promotion, contains('_promotionReasonLabel'));
    expect(promotion, contains('_invoiceNumberForDraft'));
  });
}
