import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_payout_bookkeeping_contract.dart';

void main() {
  const builder = InvoiceAwardPayoutBookkeepingProposalBuilder();

  InvoiceAwardPayoutBookkeepingProposal candidate({
    DateTime? eligibleAt,
    String fingerprint =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  }) {
    return InvoiceAwardPayoutBookkeepingProposal(
      invoiceIdentity: 'AB12345678',
      awardPeriodId: '2026-07-08',
      prizeTier: 'general-first',
      grossAmount: 200000,
      localAccountId: 'bank-local-1',
      externalRemittanceEligibleAt:
          eligibleAt ?? DateTime.utc(2026, 10, 6),
      officialDatasetFingerprint: fingerprint,
      parserRuleVersion: 'issue13-v1',
    );
  }

  test('stable idempotency key is source-domain deterministic', () {
    final value = candidate();

    expect(
      value.idempotencyKey,
      'invoice-award:2026-07-08:AB12345678:general-first',
    );
    expect(value.canCreateFormalTransaction, isFalse);
    expect(value.canConfigureMofRemittance, isFalse);
    expect(value.canClaimPrize, isFalse);
  });

  test('requires explicit authorization and external MOF remittance setup', () {
    final value = candidate();
    final now = DateTime.utc(2026, 10, 6);

    expect(
      builder.build(
        candidate: value,
        now: now,
        explicitUserAuthorization: false,
        externalMofRemittanceConfigured: true,
      ),
      isNull,
    );
    expect(
      builder.build(
        candidate: value,
        now: now,
        explicitUserAuthorization: true,
        externalMofRemittanceConfigured: false,
      ),
      isNull,
    );
  });

  test('fails closed before remittance eligibility date', () {
    final value = candidate(eligibleAt: DateTime.utc(2026, 10, 6));

    expect(
      builder.build(
        candidate: value,
        now: DateTime.utc(2026, 10, 5, 23, 59, 59),
        explicitUserAuthorization: true,
        externalMofRemittanceConfigured: true,
      ),
      isNull,
    );
  });

  test('rejects non-UTC time and invalid provenance fingerprint', () {
    final invalid = candidate(fingerprint: 'not-a-sha256');

    expect(invalid.hasValidProvenance, isFalse);
    expect(
      builder.build(
        candidate: invalid,
        now: DateTime(2026, 10, 6),
        explicitUserAuthorization: true,
        externalMofRemittanceConfigured: true,
      ),
      isNull,
    );
  });

  test('returns proposal only after all fail-closed gates pass', () {
    final value = candidate();

    final result = builder.build(
      candidate: value,
      now: DateTime.utc(2026, 10, 6),
      explicitUserAuthorization: true,
      externalMofRemittanceConfigured: true,
    );

    expect(result, same(value));
    expect(result!.canCreateFormalTransaction, isFalse);
  });
}
