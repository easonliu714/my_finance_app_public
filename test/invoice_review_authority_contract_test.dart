import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_field_first_evidence.dart';
import 'package:my_finance_app/features/invoice/invoice_review_authority_contract.dart';

void main() {
  const contract = InvoiceReviewAuthorityContract();
  const requiredFields = <InvoiceFieldFirstEvidenceKind>{
    InvoiceFieldFirstEvidenceKind.invoiceId,
    InvoiceFieldFirstEvidenceKind.issueDate,
    InvoiceFieldFirstEvidenceKind.issueTime,
    InvoiceFieldFirstEvidenceKind.totalAmount,
    InvoiceFieldFirstEvidenceKind.merchant,
    InvoiceFieldFirstEvidenceKind.lineItems,
  };

  test('QR authoritative evidence is ready for formal handoff', () {
    final decision = contract.validateRequiredFields(
      fields: InvoiceFieldFirstEvidenceKind.values.map(
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
          InvoiceFieldFirstEvidenceKind.invoiceId,
          source: InvoiceReviewAuthoritySource.explicitUserCorrection,
        ),
      ],
      requiredFields: const {InvoiceFieldFirstEvidenceKind.invoiceId},
    );

    expect(decision.isReady, isTrue);
    expect(decision.reasonCode, InvoiceReviewAuthorityReasonCode.ready);
  });

  test('explicit master selection is authoritative only for merchant', () {
    final merchantDecision = contract.validateRequiredFields(
      fields: [
        _field(
          InvoiceFieldFirstEvidenceKind.merchant,
          source: InvoiceReviewAuthoritySource.explicitMasterSelection,
        ),
      ],
      requiredFields: const {InvoiceFieldFirstEvidenceKind.merchant},
    );
    final invoiceIdDecision = contract.validateRequiredFields(
      fields: [
        _field(
          InvoiceFieldFirstEvidenceKind.invoiceId,
          source: InvoiceReviewAuthoritySource.explicitMasterSelection,
        ),
      ],
      requiredFields: const {InvoiceFieldFirstEvidenceKind.invoiceId},
    );

    expect(merchantDecision.isReady, isTrue);
    expect(invoiceIdDecision.isReady, isFalse);
    expect(
      invoiceIdDecision.reasonCode,
      InvoiceReviewAuthorityReasonCode.fieldNotAuthoritative,
    );
    expect(
      invoiceIdDecision.blockingField,
      InvoiceFieldFirstEvidenceKind.invoiceId,
    );
  });

  test('default profile remains supplemental and cannot authorize handoff', () {
    final decision = contract.validateRequiredFields(
      fields: [
        _field(
          InvoiceFieldFirstEvidenceKind.totalAmount,
          source: InvoiceReviewAuthoritySource.defaultProfile,
        ),
      ],
      requiredFields: const {InvoiceFieldFirstEvidenceKind.totalAmount},
    );

    expect(decision.isReady, isFalse);
    expect(
      decision.reasonCode,
      InvoiceReviewAuthorityReasonCode.fieldNotAuthoritative,
    );
    expect(
      decision.blockingField,
      InvoiceFieldFirstEvidenceKind.totalAmount,
    );
  });

  test('conflicting required evidence fails closed', () {
    final decision = contract.validateRequiredFields(
      fields: [
        _field(
          InvoiceFieldFirstEvidenceKind.issueDate,
          source: InvoiceReviewAuthoritySource.qrPayload,
          state: InvoiceReviewAuthorityState.conflict,
        ),
      ],
      requiredFields: const {InvoiceFieldFirstEvidenceKind.issueDate},
    );

    expect(decision.isReady, isFalse);
    expect(decision.reasonCode, InvoiceReviewAuthorityReasonCode.fieldConflict);
    expect(
      decision.blockingField,
      InvoiceFieldFirstEvidenceKind.issueDate,
    );
  });

  test('missing required evidence fails closed', () {
    final decision = contract.validateRequiredFields(
      fields: const [],
      requiredFields: const {InvoiceFieldFirstEvidenceKind.issueTime},
    );

    expect(decision.isReady, isFalse);
    expect(decision.reasonCode, InvoiceReviewAuthorityReasonCode.fieldMissing);
    expect(
      decision.blockingField,
      InvoiceFieldFirstEvidenceKind.issueTime,
    );
  });

  test('duplicate authority for the same required field fails closed', () {
    final decision = contract.validateRequiredFields(
      fields: [
        _field(
          InvoiceFieldFirstEvidenceKind.merchant,
          source: InvoiceReviewAuthoritySource.qrPayload,
        ),
        _field(
          InvoiceFieldFirstEvidenceKind.merchant,
          source: InvoiceReviewAuthoritySource.explicitUserCorrection,
        ),
      ],
      requiredFields: const {InvoiceFieldFirstEvidenceKind.merchant},
    );

    expect(decision.isReady, isFalse);
    expect(
      decision.reasonCode,
      InvoiceReviewAuthorityReasonCode.duplicateFieldAuthority,
    );
    expect(
      decision.blockingField,
      InvoiceFieldFirstEvidenceKind.merchant,
    );
  });

  test('supplemental evidence cannot authorize a required field', () {
    final decision = contract.validateRequiredFields(
      fields: [
        _field(
          InvoiceFieldFirstEvidenceKind.lineItems,
          source: InvoiceReviewAuthoritySource.qrPayload,
          state: InvoiceReviewAuthorityState.supplemental,
        ),
      ],
      requiredFields: const {InvoiceFieldFirstEvidenceKind.lineItems},
    );

    expect(decision.isReady, isFalse);
    expect(
      decision.reasonCode,
      InvoiceReviewAuthorityReasonCode.fieldNotAuthoritative,
    );
    expect(
      decision.blockingField,
      InvoiceFieldFirstEvidenceKind.lineItems,
    );
  });
}

InvoiceReviewFieldAuthority _field(
  InvoiceFieldFirstEvidenceKind kind, {
  required InvoiceReviewAuthoritySource source,
  InvoiceReviewAuthorityState state = InvoiceReviewAuthorityState.authoritative,
}) {
  return InvoiceReviewFieldAuthority(
    kind: kind,
    state: state,
    source: source,
  );
}
