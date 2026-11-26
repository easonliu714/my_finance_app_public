# Issue #13: Authorized Explicit Bank Receipt to Formal Income Posting

Owner decision (2026-10-09): Option A authorized. A **new, explicit** real-bank-credit confirmation may automatically create a formal income entry for the chosen local TWD destination. This does **not** authorize silently backfilling prior v4.20.24 test confirmations.

Atomicity and anti-duplicate: Canonical stable transaction identity is derived from period, candidate identity and award tier. Post uses the production database's transactional `ConflictAlgorithm.abort`, not the existing generic `replace` insert; a repeated action cannot overwrite or double-book. No SharedPreferences flag is taken as sufficient ledger authority; existence is determined from the canonical ledger. A crash after SQLite commit but before UI refresh is idempotently recoverable.

Prerequisites: user-visible explicit new consent; official candidate READY; exact persisted receipt evidence matches id, period, amount, source SHA, tier and account; receipt effective date is eligible and not later than authorization. TWD bank/debit account must be present, unarchived and have a unique displayName. On any failure, fail closed and do not mutate the ledger.

Existing v4.20.24 observation records remain observation-only until the user actively requests a fresh formal-posting consent in the new UI; no migration or install-time auto-post runs. Do not treat eligibility date, external MOF opt-in, or historical receipt assertion as a credit. PR #45 remains OPEN/DRAFT/Merge HOLD until exact CI+Signed Canary+owner real-device validation.
