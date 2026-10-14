# Issue #13 Cloud Review Notification and User Eligibility Confirmation

## Scope

4.20.21 winning-notification runtime is owner PASS/CLOSED. This successor
allows a cloud-exclusive `matchedReviewRequired` number match to notify the
user as a possible winner requiring eligibility review. It is never worded as
a confirmed winner.

## Notification authority

A review notification requires complete official award-domain validation, an
official cloud number match, status `matchedReviewRequired`, selected tier,
positive amount, and exact official cloud PDF SHA-256. Lock-screen content
remains privacy-minimal and excludes invoice number, merchant, transaction ID,
purchase amount, and accounting content.

Confirmed-winner dedupe keys remain unchanged to preserve the 4.20.21 owner
dedupe PASS.

## User eligibility confirmation

The production award page provides explicit local `eligible` and `ineligible`
decisions. The record binds period, governed candidate identity, candidate
source provenance, cloud tier, amount, official PDF SHA-256, decision and UTC
confirmation time. It is local-only and source-bound.

## Future payout/bookkeeping bridge

`canAuthorizeFutureBookkeepingEligibility` is only one future input. A later
automatic bookkeeping slice must additionally require validated award
authority, confirmed number match, external MOF remittance configuration and
eligible date, idempotency, and explicit product authorization.

FORMAL_ACCOUNTING_WRITE = ZERO.
PR #45 remains Draft / OPEN / Merge HOLD.
