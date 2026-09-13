import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_decision_composer.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_decision_composer_card.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_identity_review_service.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_view_model.dart';
import 'package:my_finance_app/features/invoice/invoice_transaction_handoff_contract.dart';
import 'package:my_finance_app/features/invoice/invoice_transaction_handoff_review_card.dart';
import 'package:my_finance_app/features/merchant/business_registry_repository.dart';
import 'package:my_finance_app/features/merchant/merchant_identity_resolution_policy.dart';
import 'package:my_finance_app/features/merchant/merchant_record.dart';

void main() {
  testWidgets(
      'merchant selection cannot bypass review confirmation and editable draft handoff',
      (tester) async {
    InvoiceTransactionHandoffDraft? openedDraft;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InvoiceTransactionHandoffReviewCard(
              initialReview: _review(),
              merchantIdentityReviewService: _IdentityReviewPort(),
              onOpenDraft: (draft) => openedDraft = draft,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(openedDraft, isNull);
    expect(
      find.byKey(InvoiceMerchantDecisionComposerCard.recognitionLaneKey),
      findsOneWidget,
    );
    expect(
      find.byKey(InvoiceMerchantDecisionComposerCard.existingMerchantLaneKey),
      findsOneWidget,
    );
    expect(
      find.byKey(InvoiceMerchantDecisionComposerCard.officialRegistryLaneKey),
      findsOneWidget,
    );
    expect(
      find.byKey(InvoiceTransactionHandoffReviewCard.handoffKey),
      findsNothing,
    );

    final existingSelect = find.byKey(
      InvoiceMerchantDecisionComposerCard.selectKey(
        InvoiceMerchantDecisionOption.existingMerchantBrand,
      ),
    );
    await tester.ensureVisible(existingSelect);
    await tester.tap(existingSelect);
    await tester.pumpAndSettle();

    // Merchant identity selection is review state only. It must not create a
    // transaction or even emit the editable-draft handoff callback.
    expect(openedDraft, isNull);
    expect(
      find.byKey(InvoiceTransactionHandoffReviewCard.handoffKey),
      findsNothing,
    );

    final confirmReview =
        find.byKey(InvoiceTransactionHandoffReviewCard.confirmKey);
    await tester.ensureVisible(confirmReview);
    await tester.tap(confirmReview);
    await tester.pumpAndSettle();

    // Review confirmation still does not persist a formal transaction. It only
    // unlocks the explicit editable-draft handoff action.
    expect(openedDraft, isNull);
    expect(
      find.byKey(InvoiceTransactionHandoffReviewCard.handoffKey),
      findsOneWidget,
    );

    final openDraft = find.byKey(InvoiceTransactionHandoffReviewCard.handoffKey);
    await tester.ensureVisible(openDraft);
    await tester.tap(openDraft);
    await tester.pumpAndSettle();

    expect(openedDraft, isNotNull);
    expect(openedDraft!.formalMerchantName, 'OK Mart');
  });

  testWidgets('official candidate selection alone cannot emit transaction draft',
      (tester) async {
    InvoiceTransactionHandoffDraft? openedDraft;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InvoiceTransactionHandoffReviewCard(
              initialReview: _review(),
              merchantIdentityReviewService: _IdentityReviewPort(),
              onOpenDraft: (draft) => openedDraft = draft,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final officialSelect = find.byKey(
      InvoiceMerchantDecisionComposerCard.selectKey(
        InvoiceMerchantDecisionOption.officialRegistry,
      ),
    );
    await tester.ensureVisible(officialSelect);
    await tester.tap(officialSelect);
    await tester.pumpAndSettle();

    expect(openedDraft, isNull);
    expect(
      find.byKey(InvoiceMerchantDecisionComposerCard.officialBindingConfirmKey),
      findsOneWidget,
    );
    expect(
      find.byKey(InvoiceTransactionHandoffReviewCard.handoffKey),
      findsNothing,
    );
  });
}

InvoiceReviewFormViewModel _review() {
  return const InvoiceReviewFormViewModel(
    title: 'P4.20.4 boundary fixture',
    routeReason: 'fixture',
    disclaimer: 'fixture',
    fields: <InvoiceReviewFieldViewModel>[
      InvoiceReviewFieldViewModel(
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
        value: '31655572',
        editable: true,
        requiredForReview: true,
        confidenceLabel: 'QR 解析',
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.sellerName,
        label: '商家名稱',
        value: 'OK超商 晶技門市',
        editable: true,
        requiredForReview: false,
        confidenceLabel: '本機 OCR',
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoiceDate,
        label: '發票日期',
        value: '2026-09-11',
        editable: true,
        requiredForReview: true,
        confidenceLabel: 'QR 解析',
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoiceTime,
        label: '交易時間',
        value: '13:57:00',
        editable: true,
        requiredForReview: true,
        confidenceLabel: '本機 OCR',
      ),
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.totalAmount,
        label: '總金額',
        value: '110',
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
}

class _IdentityReviewPort implements InvoiceMerchantIdentityReviewPort {
  @override
  Future<InvoiceMerchantIdentityReviewContext> resolve({
    required String sellerIdentifier,
    required bool sellerIdentifierAuthoritative,
    required String literalMerchantText,
  }) async {
    return InvoiceMerchantIdentityReviewContext(
      decision: MerchantIdentityResolutionDecision(
        literalMerchantText: literalMerchantText,
        sellerIdentifier: sellerIdentifier,
        registryLookupAllowed: true,
        officialLegalNameSuggestion: '富達零售股份有限公司晶技門市',
        formalMerchantName: 'OK Mart',
        requiresBrandConfirmation: false,
        reason: MerchantIdentityResolutionReason.confirmedBrandLink,
      ),
      registryStatus: BusinessRegistryLookupStatus.hit,
      registryVersion: 'p4.20.3-frozen-fixture',
      registryCoverage: '全台公司／商業／分公司',
      registrySourceDataDate: '2026-09-09',
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
    throw StateError('binding is outside this boundary fixture');
  }
}
