import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_identity_review_service.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_master_binding_service.dart';
import 'package:my_finance_app/features/invoice/invoice_period_policy.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_view_model.dart';
import 'package:my_finance_app/features/invoice/invoice_transaction_handoff_contract.dart';
import 'package:my_finance_app/features/invoice/invoice_transaction_handoff_review_card.dart';
import 'package:my_finance_app/features/merchant/business_registry_repository.dart';
import 'package:my_finance_app/features/merchant/merchant_identity_resolution_policy.dart';
import 'package:my_finance_app/features/merchant/merchant_record.dart';
import 'package:my_finance_app/features/merchant/merchant_seller_identity_store.dart';

void main() {
  test('invoice period derives from transaction date into six ROC bimonthly choices', () {
    expect(deriveInvoicePeriodFromDateText('2026-07-13'), '115年07-08月');
    expect(deriveInvoicePeriodFromDateText('2026/7/13'), '115年07-08月');

    final options = invoicePeriodOptionsForGregorianYear(2026);
    expect(options, hasLength(6));
    expect(options.first, '115年01-02月');
    expect(options.last, '115年11-12月');
    expect(
      options,
      <String>[
        '115年01-02月',
        '115年03-04月',
        '115年05-06月',
        '115年07-08月',
        '115年09-10月',
        '115年11-12月',
      ],
    );
  });

  test('handoff normalizes whitespace around manually entered transaction time', () {
    final review = _fullReview(
      date: '2026-06-19',
      time: '11: 35: 00',
    );
    final draft = const InvoiceTransactionHandoffContract().build(
      review: review,
      reviewConfirmed: true,
      formalMerchantName: '測試商家',
    );

    expect(draft.occurredAt, DateTime(2026, 6, 19, 11, 35));
    expect(
      draft.warnings,
      isNot(contains('INVOICE_DATE_TIME_REQUIRED_OR_INVALID')),
    );
    expect(draft.canOpenTransactionDraft, isTrue);
  });

  test('trusted QR seller identifier may bind by exact 8-digit payload even when checksum differs', () async {
    final strictStore = _FakeMerchantSellerIdentityStore();
    final strictService = InvoiceMerchantMasterBindingService(store: strictStore);
    final strict = await strictService.bind(
      merchantName: '電子發票商家',
      sellerTaxId: '60744698',
    );
    expect(strict.status, InvoiceMerchantMasterBindingStatus.invalidInput);
    expect(strictStore.rows, isEmpty);

    final qrStore = _FakeMerchantSellerIdentityStore();
    final qrService = InvoiceMerchantMasterBindingService(store: qrStore);
    final qr = await qrService.bind(
      merchantName: '電子發票商家',
      sellerTaxId: '60744698',
      trustedQrSellerIdentifier: true,
    );
    expect(qr.status, InvoiceMerchantMasterBindingStatus.created);
    expect(qr.merchant?.sellerIdentifier, '60744698');
    expect(qr.message, contains('QR provenance'));
    expect(qrStore.rows, hasLength(1));
  });

  test('traditional checksum-valid seller identifier remains accepted without QR bypass', () async {
    final store = _FakeMerchantSellerIdentityStore();
    final service = InvoiceMerchantMasterBindingService(store: store);
    final result = await service.bind(
      merchantName: '傳統發票商家',
      sellerTaxId: '30340553',
    );

    expect(result.status, InvoiceMerchantMasterBindingStatus.created);
    expect(result.merchant?.sellerIdentifier, '30340553');
  });

  test('QR bypass never overrides an existing seller-identifier conflict', () async {
    final store = _FakeMerchantSellerIdentityStore(
      <MerchantRecord>[
        MerchantRecord(
          id: 'merchant-existing',
          name: '既有商家',
          sellerIdentifier: '60744698',
        ),
      ],
    );
    final service = InvoiceMerchantMasterBindingService(store: store);
    final result = await service.bind(
      merchantName: '另一商家',
      sellerTaxId: '60744698',
      trustedQrSellerIdentifier: true,
    );

    expect(result.status, InvoiceMerchantMasterBindingStatus.conflict);
    expect(store.rows, hasLength(1));
    expect(store.rows.single.name, '既有商家');
  });

  testWidgets('blank invoice period is auto-derived and six-option period picker is available', (tester) async {
    const review = InvoiceReviewFormViewModel(
      title: '測試覆核',
      routeReason: 'test',
      disclaimer: 'test',
      fields: <InvoiceReviewFieldViewModel>[
        InvoiceReviewFieldViewModel(
          key: InvoiceReviewFieldKey.invoiceDate,
          label: '發票日期',
          value: '2026-07-13',
          editable: true,
          requiredForReview: true,
          confidenceLabel: 'QR 解析',
        ),
        InvoiceReviewFieldViewModel(
          key: InvoiceReviewFieldKey.invoiceTime,
          label: '交易時間',
          value: '',
          editable: true,
          requiredForReview: true,
          confidenceLabel: '未辨識',
        ),
        InvoiceReviewFieldViewModel(
          key: InvoiceReviewFieldKey.invoicePeriod,
          label: '發票期別',
          value: '',
          editable: true,
          requiredForReview: false,
          confidenceLabel: '未辨識',
        ),
      ],
      lineItems: <InvoiceReviewLineItemViewModel>[],
      warnings: <String>[],
      availableOverrides: [],
      canOpenReview: true,
      requiresAcknowledgement: false,
      disclaimerAcknowledged: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InvoiceTransactionHandoffReviewCard(
              initialReview: review,
              onOpenDraft: (_) {},
            ),
          ),
        ),
      ),
    );

    final periodFinder = find.byKey(
      InvoiceTransactionHandoffReviewCard.fieldKey(
        InvoiceReviewFieldKey.invoicePeriod,
      ),
    );
    final periodField = tester.widget<TextFormField>(periodFinder);
    expect(periodField.controller?.text, '115年07-08月');
    final periodEditable = tester.widget<EditableText>(
      find.descendant(of: periodFinder, matching: find.byType(EditableText)),
    );
    expect(periodEditable.readOnly, isTrue);

    final timeFinder = find.byKey(
      InvoiceTransactionHandoffReviewCard.fieldKey(
        InvoiceReviewFieldKey.invoiceTime,
      ),
    );
    final timeEditable = tester.widget<EditableText>(
      find.descendant(of: timeFinder, matching: find.byType(EditableText)),
    );
    expect(timeEditable.readOnly, isTrue);
    expect(
      find.byKey(
        InvoiceTransactionHandoffReviewCard.pickerKey(
          InvoiceReviewFieldKey.invoiceTime,
        ),
      ),
      findsOneWidget,
    );

    final periodPicker = find.byKey(
      InvoiceTransactionHandoffReviewCard.pickerKey(
        InvoiceReviewFieldKey.invoicePeriod,
      ),
    );
    await tester.ensureVisible(periodPicker);
    await tester.tap(periodPicker);
    await tester.pumpAndSettle();

    for (final option in invoicePeriodOptionsForGregorianYear(2026)) {
      expect(find.widgetWithText(ListTile, option), findsOneWidget);
    }
  });

  testWidgets('QR provenance is forwarded to merchant binding from review UI', (tester) async {
    final store = _FakeMerchantSellerIdentityStore();
    const review = InvoiceReviewFormViewModel(
      title: '電子發票覆核',
      routeReason: 'qr',
      disclaimer: 'test',
      fields: <InvoiceReviewFieldViewModel>[
        InvoiceReviewFieldViewModel(
          key: InvoiceReviewFieldKey.sellerName,
          label: '商家名稱',
          value: '7-ELEVEN 測試門市',
          editable: true,
          requiredForReview: false,
          confidenceLabel: '本機 OCR 補充',
        ),
        InvoiceReviewFieldViewModel(
          key: InvoiceReviewFieldKey.sellerTaxId,
          label: '賣方統編',
          value: '60744698',
          editable: true,
          requiredForReview: true,
          confidenceLabel: 'QR 解析',
        ),
      ],
      lineItems: <InvoiceReviewLineItemViewModel>[],
      warnings: <String>[],
      availableOverrides: [],
      canOpenReview: true,
      requiresAcknowledgement: false,
      disclaimerAcknowledged: true,
      sellerTaxIdSource: 'qr_payload',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InvoiceTransactionHandoffReviewCard(
              initialReview: review,
              onOpenDraft: (_) {},
              merchantBindingService:
                  InvoiceMerchantMasterBindingService(store: store),
              merchantIdentityReviewService:
                  const _NoopMerchantIdentityReviewPort(),
            ),
          ),
        ),
      ),
    );

    final bindButton =
        find.byKey(InvoiceTransactionHandoffReviewCard.bindMerchantKey);
    await tester.ensureVisible(bindButton);
    await tester.tap(bindButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('來源：QR 原始資料'), findsOneWidget);
    await tester.tap(find.text('確認綁定'));
    await tester.pumpAndSettle();

    expect(store.rows, hasLength(1));
    expect(store.rows.single.sellerIdentifier, '60744698');
    expect(find.textContaining('已新增商家並綁定賣方統編'), findsOneWidget);
  });
}

InvoiceReviewFormViewModel _fullReview({
  required String date,
  required String time,
}) {
  return InvoiceReviewFormViewModel(
    title: '測試覆核',
    routeReason: 'test',
    disclaimer: 'test',
    fields: <InvoiceReviewFieldViewModel>[
      const InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoiceNumber,
        label: '發票號碼',
        value: 'AB12345678',
        editable: true,
        requiredForReview: true,
        confidenceLabel: 'QR 解析',
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoiceDate,
        label: '發票日期',
        value: date,
        editable: true,
        requiredForReview: true,
        confidenceLabel: '使用者明確修正',
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoiceTime,
        label: '交易時間',
        value: time,
        editable: true,
        requiredForReview: true,
        confidenceLabel: '使用者明確修正',
      ),
      const InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.sellerTaxId,
        label: '賣方統編',
        value: '30340553',
        editable: true,
        requiredForReview: true,
        confidenceLabel: 'OCR',
      ),
      const InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.sellerName,
        label: '商家名稱',
        value: '測試商家',
        editable: true,
        requiredForReview: false,
        confidenceLabel: 'OCR',
      ),
      const InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.totalAmount,
        label: '總金額',
        value: '123',
        editable: true,
        requiredForReview: true,
        confidenceLabel: 'OCR',
      ),
      const InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoicePeriod,
        label: '發票期別',
        value: '115年05-06月',
        editable: true,
        requiredForReview: false,
        confidenceLabel: '手動',
      ),
      const InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.randomCode,
        label: '隨機碼',
        value: '',
        editable: true,
        requiredForReview: false,
        confidenceLabel: '未辨識',
      ),
    ],
    lineItems: const <InvoiceReviewLineItemViewModel>[],
    warnings: const <String>[],
    availableOverrides: const [],
    canOpenReview: true,
    requiresAcknowledgement: false,
    disclaimerAcknowledged: true,
  );
}

class _FakeMerchantSellerIdentityStore implements MerchantSellerIdentityStore {
  _FakeMerchantSellerIdentityStore([List<MerchantRecord>? seed])
      : rows = <MerchantRecord>[...?seed];

  final List<MerchantRecord> rows;

  @override
  Future<MerchantRecord?> findBySellerIdentifier(
    String sellerIdentifier, {
    bool includeArchived = false,
  }) async {
    for (final row in rows) {
      if (row.sellerIdentifier == sellerIdentifier &&
          (includeArchived || !row.isArchived)) {
        return row;
      }
    }
    return null;
  }

  @override
  Future<List<MerchantRecord>> listMerchants({
    bool includeArchived = false,
  }) async {
    return rows
        .where((row) => includeArchived || !row.isArchived)
        .toList(growable: false);
  }

  @override
  Future<void> upsertMerchant(MerchantRecord merchant) async {
    final index = rows.indexWhere((row) => row.id == merchant.id);
    if (index < 0) {
      rows.add(merchant);
    } else {
      rows[index] = merchant;
    }
  }
}

class _NoopMerchantIdentityReviewPort implements InvoiceMerchantIdentityReviewPort {
  const _NoopMerchantIdentityReviewPort();

  @override
  Future<InvoiceMerchantIdentityReviewContext> resolve({
    required String sellerIdentifier,
    required bool sellerIdentifierAuthoritative,
    required String literalMerchantText,
  }) async {
    return InvoiceMerchantIdentityReviewContext(
      decision: const MerchantIdentityResolutionPolicy().evaluate(
        sellerIdentifier: sellerIdentifier,
        sellerIdentifierAuthoritative: sellerIdentifierAuthoritative,
        literalMerchantText: literalMerchantText,
      ),
      registryStatus: BusinessRegistryLookupStatus.noInstalledRegistry,
    );
  }

  @override
  Future<InvoiceMerchantIdentityReviewContext> confirmBinding({
    required MerchantRecord merchant,
    required String sellerIdentifier,
    required String literalMerchantText,
    required String evidenceSource,
    required String sourceReference,
  }) {
    throw UnimplementedError();
  }
}
