import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_review_authority_contract.dart';

void main() {
  const contract = InvoiceReviewAuthorityContract();
  const requiredFields = <InvoiceReviewAuthorityFieldKind>{
    InvoiceReviewAuthorityFieldKind.invoiceId,
    InvoiceReviewAuthorityFieldKind.issueDate,
    InvoiceReviewAuthorityFieldKind.issueTime,
    InvoiceReviewAuthorityFieldKind.totalAmount,
    InvoiceReviewAuthorityFieldKind.merchant,
    InvoiceReviewAuthorityFieldKind.lineItems,
  };

  test('QR authoritative evidence is ready for formal handoff', () {
    final decision = contract.validateRequiredFields(
      fields: InvoiceReviewAuthorityFieldKind.values.map(
        (kind) => _field(
          kind,
          source: InvoiceReviewAuthoritySource.qrPayload,
        ),
      ),
      requiredFields: requiredFields,
    );

    expect(decision.isReady, isTrue);
    expect(decision.reasonCode, InvoiceReviewAuthorityReasonCode.ready);
    expect(decision.blockingField, isNull);
  });

  test('explicit user correction can become formal field authority', () {
    final decision = contract.validateRequiredFields(
      fields: [
        _field(
          InvoiceReviewAuthorityFieldKind.invoiceId,
          source: InvoiceReviewAuthoritySource.explicitUserCorrection,
        ),
      ],
      requiredFields: const {InvoiceReviewAuthorityFieldKind.invoiceId},
    );

    expect(decision.isReady, isTrue);
    expect(decision.reasonCode, InvoiceReviewAuthorityReasonCode.ready);
  });

  test('explicit master selection is authoritative only for merchant', () {
    final merchantDecision = contract.validateRequiredFields(
      fields: [
        _field(
          InvoiceReviewAuthorityFieldKind.merchant,
          source: InvoiceReviewAuthoritySource.explicitMasterSelection,
        ),
      ],
      requiredFields: const {InvoiceReviewAuthorityFieldKind.merchant},
    );
    final invoiceIdDecision = contract.validateRequiredFields(
      fields: [
        _field(
          InvoiceReviewAuthorityFieldKind.invoiceId,
          source: InvoiceReviewAuthoritySource.explicitMasterSelection,
        ),
      ],
      requiredFields: const {InvoiceReviewAuthorityFieldKind.invoiceId},
    );

    expect(merchantDecision.isReady, isTrue);
    expect(invoiceIdDecision.isReady, isFalse);
    expect(
      invoiceIdDecision.reasonCode,
      InvoiceReviewAuthorityReasonCode.fieldNotAuthoritative,
    );
    expect(
      invoiceIdDecision.blockingField,
      InvoiceReviewAuthorityFieldKind.invoiceId,
    );
  });

  test('default profile remains supplemental and cannot authorize handoff', () {
    final decision = contract.validateRequiredFields(
      fields: [
        _field(
          InvoiceReviewAuthorityFieldKind.totalAmount,
          source: InvoiceReviewAuthoritySource.defaultProfile,
        ),
      ],
      requiredFields: const {InvoiceReviewAuthorityFieldKind.totalAmount},
    );

    expect(decision.isReady, isFalse);
    expect(
      decision.reasonCode,
      InvoiceReviewAuthorityReasonCode.fieldNotAuthoritative,
    );
    expect(
      decision.blockingField,
      InvoiceReviewAuthorityFieldKind.totalAmount,
    );
  });

  test('conflicting required evidence fails closed', () {
    final decision = contract.validateRequiredFields(
      fields: [
        _field(
          InvoiceReviewAuthorityFieldKind.issueDate,
          source: InvoiceReviewAuthoritySource.qrPayload,
          state: InvoiceReviewAuthorityState.conflict,
        ),
      ],
      requiredFields: const {InvoiceReviewAuthorityFieldKind.issueDate},
    );

    expect(decision.isReady, isFalse);
    expect(decision.reasonCode, InvoiceReviewAuthorityReasonCode.fieldConflict);
    expect(
      decision.blockingField,
      InvoiceReviewAuthorityFieldKind.issueDate,
    );
  });

  test('missing required evidence fails closed', () {
    final decision = contract.validateRequiredFields(
      fields: const [],
      requiredFields: const {InvoiceReviewAuthorityFieldKind.issueTime},
    );

    expect(decision.isReady, isFalse);
    expect(decision.reasonCode, InvoiceReviewAuthorityReasonCode.fieldMissing);
    expect(
      decision.blockingField,
      InvoiceReviewAuthorityFieldKind.issueTime,
    );
  });

  test('duplicate authority for the same required field fails closed', () {
    final decision = contract.validateRequiredFields(
      fields: [
        _field(
          InvoiceReviewAuthorityFieldKind.merchant,
          source: InvoiceReviewAuthoritySource.qrPayload,
        ),
        _field(
          InvoiceReviewAuthorityFieldKind.merchant,
          source: InvoiceReviewAuthoritySource.explicitUserCorrection,
        ),
      ],
      requiredFields: const {InvoiceReviewAuthorityFieldKind.merchant},
    );

    expect(decision.isReady, isFalse);
    expect(
      decision.reasonCode,
      InvoiceReviewAuthorityReasonCode.duplicateFieldAuthority,
    );
    expect(
      decision.blockingField,
      InvoiceReviewAuthorityFieldKind.merchant,
    );
  });

  test('supplemental evidence cannot authorize a required field', () {
    final decision = contract.validateRequiredFields(
      fields: [
        _field(
          InvoiceReviewAuthorityFieldKind.lineItems,
          source: InvoiceReviewAuthoritySource.qrPayload,
          state: InvoiceReviewAuthorityState.supplemental,
        ),
      ],
      requiredFields: const {InvoiceReviewAuthorityFieldKind.lineItems},
    );

    expect(decision.isReady, isFalse);
    expect(
      decision.reasonCode,
      InvoiceReviewAuthorityReasonCode.fieldNotAuthoritative,
    );
    expect(
      decision.blockingField,
      InvoiceReviewAuthorityFieldKind.lineItems,
    );
  });
}

InvoiceReviewFieldAuthority _field(
  InvoiceReviewAuthorityFieldKind kind, {
  required InvoiceReviewAuthoritySource source,
  InvoiceReviewAuthorityState state = InvoiceReviewAuthorityState.authoritative,
}) {
  return InvoiceReviewFieldAuthority(
    kind: kind,
    state: state,
    source: source,
  );
}
