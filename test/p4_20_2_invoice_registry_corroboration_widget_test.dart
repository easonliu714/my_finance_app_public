import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_review.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_identity_review_service.dart';
import 'package:my_finance_app/features/invoice/invoice_registry_corroboration_policy.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_view_model.dart';
import 'package:my_finance_app/features/invoice/invoice_transaction_handoff_review_card.dart';
import 'package:my_finance_app/features/invoice/traditional_tax_id_temporal_repair.dart';
import 'package:my_finance_app/features/merchant/business_registry_repository.dart';
import 'package:my_finance_app/features/merchant/merchant_identity_resolution_policy.dart';
import 'package:my_finance_app/features/merchant/merchant_record.dart';

void main() {
  testWidgets(
      'authoritative QR seller id automatically shows official corroboration and known brand',
      (tester) async {
    final port = _FakeIdentityReviewPort(
      formalMerchantName: '一品現泡茶店',
      officialLegalName: '一品現泡茶店',
    );

    await tester.pumpWidget(
      _host(
        InvoiceTransactionHandoffReviewCard(
          initialReview: _review(
            sellerTaxId: '60744698',
            sellerTaxConfidence: 'QR 解析',
            sellerTaxIdSource:
                InvoiceRegistryCorroborationAuthorityPolicy.qrPayloadSource,
            sellerName: '發票原文：一品現泡茶店',
          ),
          merchantIdentityReviewService: port,
          onOpenDraft: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(port.resolveCalls, 1);
    expect(find.text('正式商家：一品現泡茶店'), findsOneWidget);
    expect(find.text('官方登記名稱：一品現泡茶店'), findsOneWidget);
    expect(find.text('官方資料版本：fixture-v1'), findsOneWidget);
    expect(find.text('涵蓋範圍：實機驗證子集'), findsOneWidget);
    expect(
      find.textContaining('候選商家：發票原文：一品現泡茶店'),
      findsOneWidget,
    );
    expect(
      find.textContaining('不會覆寫發票商家文字'),
      findsOneWidget,
    );
  });

  testWidgets('temporal Local seller-id provenance can corroborate automatically',
      (tester) async {
    final port = _FakeIdentityReviewPort(
      formalMerchantName: '',
      officialLegalName: 'Temporal 官方名稱',
    );

    await tester.pumpWidget(
      _host(
        InvoiceTransactionHandoffReviewCard(
          initialReview: _review(
            sellerTaxId: '30340553',
            sellerTaxConfidence: '本機 OCR',
            sellerTaxIdSource: positionalTaxIdTemporalRepairSource,
            sellerName: '發票原文商家',
          ),
          merchantIdentityReviewService: port,
          onOpenDraft: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(port.resolveCalls, 1);
    expect(find.text('官方登記名稱：Temporal 官方名稱'), findsOneWidget);
  });

  testWidgets('AI seller id performs zero registry lookup before global acknowledgement',
      (tester) async {
    final port = _FakeIdentityReviewPort(
      formalMerchantName: '',
      officialLegalName: 'AI 統編官方名稱',
    );
    final acknowledged = ValueNotifier<bool>(false);
    addTearDown(acknowledged.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: acknowledged,
            builder: (context, value, _) => SingleChildScrollView(
              child: InvoiceTransactionHandoffReviewCard(
                key: const ValueKey<String>('p4-20-2-card'),
                initialReview: _review(
                  sellerTaxId: '',
                  sellerTaxConfidence: '未辨識',
                  sellerTaxIdSource: '',
                  sellerName: '發票原文商家',
                ),
                aiComparisonRequired: true,
                aiComparisonAcknowledged: value,
                aiCandidate: const GeminiInvoiceReviewCandidate(
                  invoiceNumber: 'AB12345678',
                  invoicePeriod: '115年07-08月',
                  sellerTaxId: '30340553',
                  invoiceDate: '2026-08-31',
                  invoiceTime: '17:00',
                  merchantName: 'AI 商家候選',
                  totalAmount: 110,
                  lineItems: <GeminiInvoiceReviewLineItem>[],
                  confidence: <GeminiInvoiceReviewField, double>{},
                  warnings: <String>[],
                ),
                merchantIdentityReviewService: port,
                onOpenDraft: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(port.resolveCalls, 0);

    final switchFinder = find.byKey(
      InvoiceTransactionHandoffReviewCard.sourceSwitchKey(
        InvoiceReviewFieldKey.sellerTaxId,
      ),
    );
    expect(switchFinder, findsOneWidget);
    await tester.tap(
      find.descendant(
        of: switchFinder,
        matching: find.byKey(const Key('invoice_source_switch_ai')),
      ),
    );
    await tester.pumpAndSettle();

    expect(port.resolveCalls, 0);
    expect(
      find.textContaining('尚未符合官方資料查詢權威'),
      findsOneWidget,
    );

    acknowledged.value = true;
    await tester.pumpAndSettle();

    expect(port.resolveCalls, 1);
    expect(find.text('官方登記名稱：AI 統編官方名稱'), findsOneWidget);
  });

  testWidgets('manual seller-id mutation invalidates stale official result',
      (tester) async {
    final port = _FakeIdentityReviewPort(
      formalMerchantName: '原正式商家',
      officialLegalName: '原官方名稱',
    );

    await tester.pumpWidget(
      _host(
        InvoiceTransactionHandoffReviewCard(
          initialReview: _review(
            sellerTaxId: '30340553',
            sellerTaxConfidence: '本機 OCR',
            sellerTaxIdSource:
                InvoiceRegistryCorroborationAuthorityPolicy
                    .traditionalExplicitLabelSource,
            sellerName: '發票原文商家',
          ),
          merchantIdentityReviewService: port,
          onOpenDraft: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('官方登記名稱：原官方名稱'), findsOneWidget);

    final taxField = find.byKey(
      InvoiceTransactionHandoffReviewCard.fieldKey(
        InvoiceReviewFieldKey.sellerTaxId,
      ),
    );
    await tester.enterText(taxField, '60744698');
    await tester.pumpAndSettle();

    expect(find.text('官方登記名稱：原官方名稱'), findsNothing);
    expect(find.text('正式商家：原正式商家'), findsNothing);
    expect(
      find.textContaining('尚未符合官方資料查詢權威'),
      findsOneWidget,
    );
  });

  testWidgets('checksum-valid value without provenance never starts registry lookup',
      (tester) async {
    final port = _FakeIdentityReviewPort(
      formalMerchantName: '不應出現',
      officialLegalName: '不應出現',
    );

    await tester.pumpWidget(
      _host(
        InvoiceTransactionHandoffReviewCard(
          initialReview: _review(
            sellerTaxId: '30340553',
            sellerTaxConfidence: '高',
            sellerTaxIdSource: '',
            sellerName: '無 provenance fixture',
          ),
          merchantIdentityReviewService: port,
          onOpenDraft: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(port.resolveCalls, 0);
    expect(find.textContaining('尚未符合官方資料查詢權威'), findsOneWidget);
  });
}

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: child),
    ),
  );
}

InvoiceReviewFormViewModel _review({
  required String sellerTaxId,
  required String sellerTaxConfidence,
  required String sellerTaxIdSource,
  required String sellerName,
}) {
  return InvoiceReviewFormViewModel(
    title: 'fixture',
    routeReason: 'fixture',
    disclaimer: 'fixture',
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
        key: InvoiceReviewFieldKey.sellerTaxId,
        label: '賣方統編',
        value: sellerTaxId,
        editable: true,
        requiredForReview: true,
        confidenceLabel: sellerTaxConfidence,
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.sellerName,
        label: '商家名稱',
        value: sellerName,
        editable: true,
        requiredForReview: false,
        confidenceLabel: '本機 OCR',
      ),
      const InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoiceDate,
        label: '發票日期',
        value: '2026-08-31',
        editable: true,
        requiredForReview: true,
        confidenceLabel: 'QR 解析',
      ),
      const InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoiceTime,
        label: '交易時間',
        value: '17:00:00',
        editable: true,
        requiredForReview: true,
        confidenceLabel: '本機 OCR',
      ),
      const InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.totalAmount,
        label: '總金額',
        value: '110',
        editable: true,
        requiredForReview: true,
        confidenceLabel: 'QR 解析',
      ),
    ],
    lineItems: const <InvoiceReviewLineItemViewModel>[],
    warnings: const <String>[],
    availableOverrides: const [],
    canOpenReview: true,
    requiresAcknowledgement: false,
    disclaimerAcknowledged: true,
    sellerTaxIdSource: sellerTaxIdSource,
  );
}

class _FakeIdentityReviewPort implements InvoiceMerchantIdentityReviewPort {
  _FakeIdentityReviewPort({
    required this.formalMerchantName,
    required this.officialLegalName,
  });

  final String formalMerchantName;
  final String officialLegalName;
  int resolveCalls = 0;

  @override
  Future<InvoiceMerchantIdentityReviewContext> resolve({
    required String sellerIdentifier,
    required bool sellerIdentifierAuthoritative,
    required String literalMerchantText,
  }) async {
    resolveCalls += 1;
    return InvoiceMerchantIdentityReviewContext(
      decision: MerchantIdentityResolutionDecision(
        literalMerchantText: literalMerchantText,
        sellerIdentifier: sellerIdentifier,
        registryLookupAllowed: true,
        officialLegalNameSuggestion: officialLegalName,
        formalMerchantName: formalMerchantName,
        requiresBrandConfirmation: formalMerchantName.isEmpty,
        reason: formalMerchantName.isEmpty
            ? MerchantIdentityResolutionReason.registryLegalNameNeedsBrandConfirmation
            : MerchantIdentityResolutionReason.confirmedBrandLink,
      ),
      registryStatus: BusinessRegistryLookupStatus.hit,
      registryVersion: 'fixture-v1',
      registryCoverage: 'validation_subset',
      registrySourceDataDate: '2025-06-02',
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
