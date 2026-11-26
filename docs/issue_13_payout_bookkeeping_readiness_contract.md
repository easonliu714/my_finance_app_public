# Issue #13 Payout Bookkeeping Readiness and Auto-Posting Preflight

## Purpose

This slice follows owner-PASS 4.20.22 cloud eligibility confirmation. It
connects confirmed award results to a local, idempotent bookkeeping readiness
proposal without creating a formal accounting transaction.

## User settings

The local preflight stores:

- automatic prize bookkeeping opt-in;
- assertion that Ministry-of-Finance-side automatic remittance is configured;
- destination local TWD account id used only to represent the future bookkeeping
  inflow.

The local account setting does not configure, modify, or claim an MOF remittance
account.

## Eligibility

A proposal can become READY only when:

1. automatic bookkeeping is opted in;
2. a local destination account is selected;
3. the user asserts external MOF remittance is configured;
4. general and cloud award authorities are complete;
5. the governed redemption-start instant has arrived;
6. official provenance fingerprint/parser lineage is valid;
7. a cloud matchedReviewRequired prize has persisted user eligibility=eligible.

Raw matchedReviewRequired never authorizes readiness.

When a candidate has multiple confirmed prize options, the planner keeps one
deterministic highest-amount option, preserving the existing one-prize-per-
invoice behavior and a stable idempotency key.

## Accounting boundary

This slice is preview/readiness only:

- FORMAL_ACCOUNTING_WRITE=ZERO
- no transaction INSERT/UPDATE/DELETE
- no claim/redemption execution
- no MOF account configuration
- no DB schema migration

Formal automatic posting is a later separately owner-validated and authorized
slice.
