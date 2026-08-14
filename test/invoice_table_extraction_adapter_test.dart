import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/invoice_table_extraction_adapter.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 6, 17, 12);
  final adapter = LabInvoiceTableExtractionAdapter(clock: () => fixedNow);

  test('normalizes a supported selected row into a private lab candidate', () {
    final preview = adapter.createPreview(
      LabInvoiceTableSelection(
        schemaId: labInvoiceTableSchemaV1,
        rows: <LabInvoiceTableRowInput>[
          _validRow(),
        ],
      ),
    );

    expect(preview.detectedRowCount, 1);
    expect(preview.supportedRowCount, 1);
    expect(preview.blockedRowCount, 0);
    expect(preview.canImport, isTrue);
    expect(preview.canCreateFormalTransactionAutomatically, isFalse);

    final candidate = preview.rows.single.candidate!;
    expect(candidate.source, CloudInvoiceCandidateSource.privateCloudResearch);
    expect(candidate.status, CloudInvoiceCandidateStatus.pending);
    expect(candidate.invoiceNumber, 'AB12345678');
    expect(candidate.invoiceDate, DateTime(2026, 6, 17, 14, 35));
    expect(candidate.sellerIdentifier, '12345678');
    expect(candidate.sellerName, '測試商店');
    expect(candidate.totalAmount, 120);
    expect(candidate.taxAmount, 6);
    expect(candidate.carrierMaskedId, '****3456');
    expect(candidate.fetchedAt, fixedNow);
    expect(candidate.rawPayload, isNull);
    expect(candidate.lineItems, hasLength(2));
    expect(candidate.canCreateFormalTransactionAutomatically, isFalse);
  });

  test('accepts ROC date and compact time formats', () {
    final preview = adapter.createPreview(
      LabInvoiceTableSelection(
        schemaId: labInvoiceTableSchemaV1,
        rows: <LabInvoiceTableRowInput>[
          _validRow(
            rowId: 'roc-row',
            invoiceDate: '1150617',
            invoiceTime: '143501',
          ),
        ],
      ),
    );

    expect(preview.rows.single.isSupported, isTrue);
    expect(
      preview.rows.single.candidate!.invoiceDate,
      DateTime(2026, 6, 17, 14, 35, 1),
    );
  });

  test('blocks malformed invoice, date, time, and amount', () {
    final preview = adapter.createPreview(
      const LabInvoiceTableSelection(
        schemaId: labInvoiceTableSchemaV1,
        rows: <LabInvoiceTableRowInput>[
          LabInvoiceTableRowInput(
            rowId: 'bad-row',
            invoiceNumber: '123',
            invoiceDate: '2026-02-31',
            invoiceTime: '25:90',
            totalAmount: 'not-money',
          ),
        ],
      ),
    );

    final row = preview.rows.single;
    expect(row.isBlocked, isTrue);
    expect(row.candidate, isNull);
    expect(
      row.issues.map((issue) => issue.code),
      containsAll(<LabInvoiceTableIssueCode>[
        LabInvoiceTableIssueCode.invalidInvoiceNumber,
        LabInvoiceTableIssueCode.invalidInvoiceDate,
        LabInvoiceTableIssueCode.invalidInvoiceTime,
        LabInvoiceTableIssueCode.invalidTotalAmount,
      ]),
    );
    expect(preview.importAllSupported(), isEmpty);
  });

  test('keeps partial rows reviewable with warnings', () {
    final preview = adapter.createPreview(
      LabInvoiceTableSelection(
        schemaId: labInvoiceTableSchemaV1,
        rows: <LabInvoiceTableRowInput>[
          _validRow(
            rowId: 'partial-row',
            sellerName: '',
            sellerIdentifier: '123',
            lineItems: const <LabInvoiceTableLineItemInput>[
              LabInvoiceTableLineItemInput(
                name: '',
                amount: '30',
              ),
            ],
          ),
        ],
      ),
    );

    final row = preview.rows.single;
    expect(row.isSupported, isTrue);
    expect(
      row.issues.map((issue) => issue.code),
      containsAll(<LabInvoiceTableIssueCode>[
        LabInvoiceTableIssueCode.invalidSellerIdentifier,
        LabInvoiceTableIssueCode.missingSellerName,
        LabInvoiceTableIssueCode.missingLineItems,
        LabInvoiceTableIssueCode.partialLineItems,
      ]),
    );
    expect(
      row.candidate!.warnings,
      containsAll(<CloudInvoiceCandidateWarning>[
        CloudInvoiceCandidateWarning.missingSellerName,
        CloudInvoiceCandidateWarning.missingLineItems,
        CloudInvoiceCandidateWarning.partialPayload,
      ]),
    );
  });

  test('marks later duplicate rows deterministically', () {
    final preview = adapter.createPreview(
      LabInvoiceTableSelection(
        schemaId: labInvoiceTableSchemaV1,
        rows: <LabInvoiceTableRowInput>[
          _validRow(rowId: 'first'),
          _validRow(rowId: 'second'),
        ],
      ),
    );

    expect(preview.supportedRowCount, 2);
    expect(preview.duplicateHintCount, 1);
    expect(
      preview.rows.first.candidate!.status,
      CloudInvoiceCandidateStatus.pending,
    );
    expect(
      preview.rows.last.candidate!.status,
      CloudInvoiceCandidateStatus.duplicate,
    );
    expect(preview.rows.last.duplicateOfRowId, 'first');
  });

  test('blocks a repeated row identifier', () {
    final preview = adapter.createPreview(
      LabInvoiceTableSelection(
        schemaId: labInvoiceTableSchemaV1,
        rows: <LabInvoiceTableRowInput>[
          _validRow(rowId: 'same'),
          _validRow(rowId: 'same', invoiceNumber: 'CD87654321'),
        ],
      ),
    );

    expect(preview.supportedRowCount, 1);
    expect(preview.blockedRowCount, 1);
    expect(
      preview.rows.last.issues.single.code,
      LabInvoiceTableIssueCode.duplicateRowId,
    );
  });

  test('imports only explicitly selected supported rows', () {
    final preview = adapter.createPreview(
      LabInvoiceTableSelection(
        schemaId: labInvoiceTableSchemaV1,
        rows: <LabInvoiceTableRowInput>[
          _validRow(rowId: 'one'),
          _validRow(
            rowId: 'two',
            invoiceNumber: 'CD87654321',
            totalAmount: '80',
          ),
        ],
      ),
    );

    final selected = preview.importSelected(<String>{'two', 'missing'});
    expect(selected, hasLength(1));
    expect(selected.single.invoiceNumber, 'CD87654321');
    expect(preview.importAllSupported(), hasLength(2));
    expect(preview.cancel(), isEmpty);
  });

  test('unsupported schema blocks the entire preview', () {
    final preview = adapter.createPreview(
      LabInvoiceTableSelection(
        schemaId: 'unknown.table.v9',
        rows: <LabInvoiceTableRowInput>[
          _validRow(),
        ],
      ),
    );

    expect(preview.isBlocked, isTrue);
    expect(preview.canImport, isFalse);
    expect(preview.supportedRowCount, 0);
    expect(preview.blockedRowCount, 1);
    expect(preview.importAllSupported(), isEmpty);
  });

  test('already masked carrier display is preserved', () {
    final preview = adapter.createPreview(
      LabInvoiceTableSelection(
        schemaId: labInvoiceTableSchemaV1,
        rows: <LabInvoiceTableRowInput>[
          _validRow(carrierDisplay: '/AB****12'),
        ],
      ),
    );

    expect(preview.rows.single.candidate!.carrierMaskedId, '/AB****12');
  });
}

LabInvoiceTableRowInput _validRow({
  String rowId = 'row-1',
  String invoiceNumber = 'AB-12345678',
  String invoiceDate = '2026/06/17',
  String invoiceTime = '14:35',
  String sellerIdentifier = '12345678',
  String sellerName = '測試商店',
  String totalAmount = 'NT\$ 120',
  String taxAmount = '6',
  String carrierDisplay = '/ABCD123456',
  List<LabInvoiceTableLineItemInput> lineItems = const <LabInvoiceTableLineItemInput>[
    LabInvoiceTableLineItemInput(
      name: '咖啡',
      amount: '55',
      quantity: '1',
      unitPrice: '55',
    ),
    LabInvoiceTableLineItemInput(
      name: '麵包',
      amount: '65',
      quantity: '1',
      unitPrice: '65',
    ),
  ],
}) {
  return LabInvoiceTableRowInput(
    rowId: rowId,
    invoiceNumber: invoiceNumber,
    invoiceDate: invoiceDate,
    invoiceTime: invoiceTime,
    sellerIdentifier: sellerIdentifier,
    sellerName: sellerName,
    totalAmount: totalAmount,
    taxAmount: taxAmount,
    carrierType: 'mobile_barcode',
    carrierDisplay: carrierDisplay,
    lineItems: lineItems,
  );
}
