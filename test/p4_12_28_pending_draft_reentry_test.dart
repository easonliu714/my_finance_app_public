import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v16.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_persistence_models.dart';
import 'package:my_finance_app/features/invoice/lab/official_cloud_invoice_csv_adapter.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_csv_import_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('CSV re-entry reuses a pending draft instead of conflicting', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('CREATE TABLE transactions (id TEXT PRIMARY KEY)');
    await createCanonicalProductionV16Tables(db);
    await db.insert('cloud_invoice_drafts', <String, Object?>{
      'id': 'draft-existing',
      'operation_key': 'cloud-invoice-existing',
      'candidate_reference': 'candidate-existing',
      'account_id': '',
      'account_name': '',
      'amount': 90,
      'invoice_date': DateTime.utc(2026, 6, 17).toIso8601String(),
      'time_precision': 'dateOnly',
      'time_source': 'unknown',
      'currency_code': null,
      'currency_source': 'unknown',
      'merchant_id': null,
      'invoice_number': 'BS-9000 0016',
      'seller_identifier': '12345678',
      'seller_name': '百樂商行',
      'tax_amount': null,
      'line_items_json': '[]',
      'payload_version': 1,
      'account_resolution_status': 'unresolved',
      'created_at': DateTime.utc(2026, 6, 27).toIso8601String(),
    });

    final service = PrivateCloudInvoiceCsvImportService(
      databaseProvider: () async => db,
    );
    final preview = OfficialCloudInvoiceCsvPreview(
      invoices: <OfficialCloudInvoiceCsvInvoicePreview>[
        OfficialCloudInvoiceCsvInvoicePreview(
          id: 'BS90000016',
          carrierName: '手機條碼',
          invoiceStatus: '正常',
          discountFlag: '',
          sellerAddress: '',
          buyerIdentifier: '',
          detailRowCount: 1,
          issues: const <OfficialCloudInvoiceCsvIssue>[],
          candidate: CloudInvoiceCandidate(
            source: CloudInvoiceCandidateSource.privateCloudResearch,
            status: CloudInvoiceCandidateStatus.pending,
            invoiceNumber: 'BS90000016',
            invoiceDate: DateTime.utc(2026, 6, 17),
            sellerIdentifier: '12345678',
            sellerName: '百樂商行',
            totalAmount: 90,
            carrierType: 'official-csv',
            carrierMaskedId: '',
            fetchedAt: DateTime.utc(2026, 6, 28),
            lineItems: const <CloudInvoiceLineItem>[
              CloudInvoiceLineItem(name: '巧克力餅', amount: 90),
            ],
          ),
        ),
      ],
      fileIssues: const <OfficialCloudInvoiceCsvIssue>[],
      detailRowCount: 1,
      repairedRowCount: 0,
      ignoredFooterCount: 0,
      earliestInvoiceDate: DateTime.utc(2026, 6, 17),
      latestInvoiceDate: DateTime.utc(2026, 6, 17),
    );

    final summary = await service.importDrafts(
      preview: preview,
      invoiceIds: const <String>{'BS90000016'},
      account: const AccountRecord(
        id: 'account-cash',
        name: '現金',
        type: AccountType.cash,
        initialBalance: 0,
        sortOrder: 0,
      ),
    );

    expect(summary.committedCount, 0);
    expect(summary.replayCount, 1);
    expect(summary.rejectedCount, 0);
    expect(summary.pendingDraftIds, {'draft-existing'});
    expect(
      summary.results.single.status,
      CloudInvoicePersistenceStatus.alreadyApplied,
    );
    expect(summary.results.single.message, 'CSV_INVOICE_DRAFT_ALREADY_PENDING');
    expect(summary.results.single.accountId, 'account-cash');
    expect(summary.invoiceNumberFor(summary.results.single), 'BS90000016');
    final inheritedRows = await db.query(
      'cloud_invoice_drafts',
      columns: const <String>[
        'account_id',
        'account_name',
        'account_resolution_status',
      ],
      where: 'id = ?',
      whereArgs: const <Object?>['draft-existing'],
    );
    expect(inheritedRows.single['account_id'], 'account-cash');
    expect(inheritedRows.single['account_name'], '現金');
    expect(inheritedRows.single['account_resolution_status'], 'selected');
    final count = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM cloud_invoice_drafts',
    );
    expect((count.single['total'] as num).toInt(), 1);
  });

  test('CSV re-entry preserves an already selected draft account', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('CREATE TABLE transactions (id TEXT PRIMARY KEY)');
    await createCanonicalProductionV16Tables(db);
    await db.insert('cloud_invoice_drafts', <String, Object?>{
      'id': 'draft-selected',
      'operation_key': 'cloud-invoice-selected',
      'candidate_reference': 'candidate-selected',
      'account_id': 'account-credit',
      'account_name': '信用卡',
      'amount': 90,
      'invoice_date': DateTime.utc(2026, 6, 17).toIso8601String(),
      'time_precision': 'dateOnly',
      'time_source': 'unknown',
      'currency_code': null,
      'currency_source': 'unknown',
      'merchant_id': null,
      'invoice_number': 'BS90000016',
      'seller_identifier': '12345678',
      'seller_name': '百樂商行',
      'tax_amount': null,
      'line_items_json': '[]',
      'payload_version': 1,
      'account_resolution_status': 'selected',
      'created_at': DateTime.utc(2026, 6, 27).toIso8601String(),
    });

    final service = PrivateCloudInvoiceCsvImportService(
      databaseProvider: () async => db,
    );
    final preview = OfficialCloudInvoiceCsvPreview(
      invoices: <OfficialCloudInvoiceCsvInvoicePreview>[
        OfficialCloudInvoiceCsvInvoicePreview(
          id: 'BS90000016',
          carrierName: '手機條碼',
          invoiceStatus: '正常',
          discountFlag: '',
          sellerAddress: '',
          buyerIdentifier: '',
          detailRowCount: 1,
          issues: const <OfficialCloudInvoiceCsvIssue>[],
          candidate: CloudInvoiceCandidate(
            source: CloudInvoiceCandidateSource.privateCloudResearch,
            status: CloudInvoiceCandidateStatus.pending,
            invoiceNumber: 'BS90000016',
            invoiceDate: DateTime.utc(2026, 6, 17),
            sellerIdentifier: '12345678',
            sellerName: '百樂商行',
            totalAmount: 90,
            carrierType: 'official-csv',
            carrierMaskedId: '',
            fetchedAt: DateTime.utc(2026, 6, 28),
            lineItems: const <CloudInvoiceLineItem>[
              CloudInvoiceLineItem(name: '巧克力餅', amount: 90),
            ],
          ),
        ),
      ],
      fileIssues: const <OfficialCloudInvoiceCsvIssue>[],
      detailRowCount: 1,
      repairedRowCount: 0,
      ignoredFooterCount: 0,
      earliestInvoiceDate: DateTime.utc(2026, 6, 17),
      latestInvoiceDate: DateTime.utc(2026, 6, 17),
    );

    final summary = await service.importDrafts(
      preview: preview,
      invoiceIds: const <String>{'BS90000016'},
      account: const AccountRecord(
        id: 'account-cash',
        name: '現金',
        type: AccountType.cash,
        initialBalance: 0,
        sortOrder: 0,
      ),
    );

    expect(summary.replayCount, 1);
    expect(summary.results.single.accountId, 'account-credit');
    final rows = await db.query(
      'cloud_invoice_drafts',
      columns: const <String>[
        'account_id',
        'account_name',
        'account_resolution_status',
      ],
      where: 'id = ?',
      whereArgs: const <Object?>['draft-selected'],
    );
    expect(rows.single['account_id'], 'account-credit');
    expect(rows.single['account_name'], '信用卡');
    expect(rows.single['account_resolution_status'], 'selected');
  });
}
