# Issue #13 / 4.20.27 — Posted Ledger Audit & Consent Copy

## Incoming owner evidence (2026-10-11)

4.20.26+484 is owner-observed PASS for canonical POSTED display and the absence
of duplicate prize-income transactions on repeated award checking. Previous
4.20.25 owner acceptance established an NT$500 cloud award and NT$200 general
award, totaling NT$700 in the selected local ledger. This is local ledger
evidence, **not** an independent external bank-statement verification.

The 4.20.26 exact authority is PR #45 commit
`ba3dade83f864130009a222a1ed98b769881d4ba`. CI #963 and true Signed
Canary #327 were successful. The signed ZIP digest matches GitHub artifact
11694604875, and the embedded APK SHA matches its checksum. Both metadata
statements are present:
`FORMAL_ACCOUNTING_WRITE=EXPLICIT_USER_CONFIRMED_ONLY`;
`LEGACY_RECEIPT_AUTO_BACKFILL=ZERO`.

## 4.20.27 authorized slice (read-only precursor)

1. Compare a **caller-read canonical** posted ledger record with the validated
   user receipt observation and exact authoritative prize proposal.
2. Distinguish missing ledger row, wrong stable identity, type/currency,
   amount, display account, received date, and note provenance mismatches.
3. A consistent local ledger record is `postedLocalOnly`. It never proves
   an actual bank credit. Local `accountName` does not independently attest
   to a bank's external account number or account ID.
4. A mismatch is diagnostic/review only. Do not create, move, replace,
   reverse, delete, auto-repair, or auto-backfill a formal transaction.
5. Correct 4.20.23-era user-facing copy that incorrectly implied the **whole
   App version** cannot post a transaction. Each stage now states its own
   precise authority: candidate preparation does not post; manual receipt
   observation does not post; a separate explicit confirmation may post.

The pure `InvoiceAwardPostedLedgerAudit.evaluate` does not query/write DB or
persist evidence. It is a tested building block, **not yet wired into the
production page or a bank statement/import reconciliation feed**. Until a
separate read-only source and UI integration Gate is validated, do not claim
that reconciliation is already visible in production.

## Nonregression

- Keep the 4.20.26 canonical `POSTED` identity lookup intact.
- Keep `db.transaction<bool>` and `ConflictAlgorithm.abort`.
- Never derive actual bank settlement from user-configured MOF opt-in,
  eligibility date, SharedPreferences, receipt observation, or a ledger row.
- Require new explicit user authorization for any new formal income insert.
- Do not automatically book earlier historical/test receipt observations.
- Keep PR #45 Draft/OPEN/Merge HOLD. Owner authorizes feature progress, not
  merging to `main`.

## Next validation Gate

Fresh-read HEAD and run `flutter analyze`, focused read-only audit/copy
tests, full `flutter test`, and debug APK build. Then true Signed Canary
with exact release version `4.20.27+485` and independently inspect ZIP,
metadata, APK checksum, signer and permission gates. Device verification
should focus on corrected copy while preserving NT$500+200 existing income
and the canonical POSTED state. Read-side audit UI integration and genuine
bank statement reconciliation are separate future gates.
