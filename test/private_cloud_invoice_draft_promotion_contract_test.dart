import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v14 schema records immutable draft promotion links', () {
    final schema = File(
      'lib/database/production_schema_v14.dart',
    ).readAsStringSync();

    expect(schema, contains('canonicalProductionSchemaVersion = 14'));
    expect(schema, contains('cloud_invoice_draft_promotions'));
    expect(schema, contains('draft_id TEXT PRIMARY KEY'));
    expect(schema, contains('transaction_id TEXT NOT NULL UNIQUE'));
    expect(schema, contains('draft_fingerprint TEXT NOT NULL'));
  });

  test('promotion writes transaction metadata and marker in one transaction', () {
    final source = File(
      'lib/features/invoice/lab/private_cloud_invoice_draft_promotion_service.dart',
    ).readAsStringSync();

    expect(source, contains('db.transaction'));
    expect(
      source,
      matches(RegExp(r"transaction\s*\.\s*insert\(\s*'transactions'")),
    );
    expect(
      source,
      matches(
        RegExp(
          r"transaction\s*\.\s*insert\(\s*'cloud_invoice_metadata_links'",
        ),
      ),
    );
    expect(
      source,
      matches(
        RegExp(
          r"transaction\s*\.\s*insert\(\s*'cloud_invoice_draft_promotions'",
        ),
      ),
    );
    expect(source, contains('POTENTIAL_DUPLICATE_REVIEW_REQUIRED'));
    expect(source, contains('ACCOUNT_REQUIRED_FOR_NEW_TRANSACTION'));
    expect(source, contains('DRAFT_ALREADY_PROMOTED'));
    expect(source, isNot(contains('AND t.account_name = ?')));
    expect(source, isNot(contains("delete(\n        'cloud_invoice_drafts'")));
    expect(source, isNot(contains('MerchantRepository')));
  });

  test('promotion UI requires review, conflict routing, and confirmation', () {
    final page = File(
      'lib/features/invoice/lab/private_cloud_invoice_draft_promotion_page.dart',
    ).readAsStringSync();
    final conflictPage = File(
      'lib/features/invoice/lab/private_cloud_invoice_conflict_review_page.dart',
    ).readAsStringSync();
    final lab = File(
      'lib/features/invoice/lab/private_cloud_invoice_lab_page.dart',
    ).readAsStringSync();

    expect(page, contains('查看完整品項'));
    expect(page, contains('批次付款帳戶（選填）'));
    expect(page, contains('批次分類'));
    expect(page, contains('批次成員'));
    expect(page, contains('批次標籤'));
    expect(
      page,
      contains('我確認先比對既有交易，並將資料完整者建立為正式支出'),
    );
    expect(page, contains('付款帳戶（建立新交易時必填）'));
    expect(page, contains('跨帳戶檢查同日期、同金額交易'));
    expect(page, contains('conflictReviewKey'));
    expect(conflictPage, contains('我確認套用'));
    expect(conflictPage, contains('系統不會自動覆蓋'));
    expect(lab, contains('draftPromotionButtonKey'));
    expect(lab, contains('開啟草稿轉正式覆核'));
  });
}
