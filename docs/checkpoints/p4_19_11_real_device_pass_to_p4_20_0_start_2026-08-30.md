# Finance App Micro Checkpoint

Date: 2026-08-30
Transition: P4.19.11 OWNER_REAL_DEVICE_PASS -> P4.20.0-A MERCHANT_IDENTITY_CONTRACT_START

## P4.19.11 frozen authority

- Version: `4.19.11+452`
- Exact head: `d4013f390dea7d66099a55e6817ddfc290d430e2`
- Flutter Android CI run `33132605612`: PASS
- P4.19.11 Public Signed Canary run `33132605634`: PASS
- APK SHA-256: `e4a2725616764b49dfb7b7ceb2cc68b972944e0b61849c0dd0c6871b6fecf6fa`
- Signing certificate SHA-256: `9BA2CA64E4218795A4313EFB8FDC020011DCEAE0C70F6F0614DF28328BBEDEB7`
- Owner real-device validation: PASS on 2026-08-30
- Returned evidence: `v4.19.11.zip`, 11 screenshots

Real-device evidence visibly covers installed version 4.19.11, electronic QR review, QR seller-identifier merchant binding, date-derived ROC period, date/time pickers, six-period selector, traditional merchant binding, and reviewed invoice handoff into an editable transaction draft.

Decision: `P4.19.11+452 = FROZEN / AUTOMATED_GREEN / REAL_DEVICE_GREEN`

PR #37 remains Draft / Open / Unmerged. Real-device gate is closed, but merge authority remains separate and explicit.

## P4.20.0-A start

Roadmap authority: public issue #20, `merchant identity history, downloadable official business registry, and local learning`.

Branch: `p4-20-0-merchant-identity-foundation`
Base: exact P4.19.11 frozen head.

### Goal

Establish an executable, fail-closed merchant identity and official-registry contract before any production DB migration or network registry update is enabled.

Required identity separation:

```text
literal invoice merchant text
        | preserved observation
        v
MerchantBrand <-> LegalEntity <-> BranchOrOutlet
        ^             ^
        |             |
user-confirmed        official registry corroboration
bookkeeping identity  for authoritative seller id only
```

### P4.20.0-A initial implementation

- candidate V22 merchant identity schema is executable in tests but is intentionally **not installed into AccountRepository yet**;
- existing `merchants.id` is preserved as the candidate `merchant_brands.id` so historical/current merchant references are not rewritten;
- explicit P4.19.11 seller-identifier bindings migrate as confirmed Brand↔LegalEntity links with provenance;
- literal identity observations are append-only;
- official registry snapshot/entities/negative-cache tables are separated from user-owned merchant identity tables and can be replaced independently;
- registry lookup policy only runs after seller-identifier authority already exists;
- official legal name remains a labeled suggestion and cannot silently overwrite literal invoice text or create a MerchantBrand mapping;
- existing confirmed brand mapping may be reused for an authoritative seller id;
- negative registry lookup identity is version scoped;
- no network acquisition, no official dataset ingestion, no production schemaVersion bump, no transaction write, and no migration of the live user DB in this A gate.

### Next gates

1. P4.20.0-A Analyze + focused contract/schema tests + full CI.
2. P4.20.0-B production schema V22 migration/rollback/backup round-trip and canonical schemaVersion activation.
3. P4.20.0-C replaceable official registry pack ingestion + manifest/SHA validation + local lookup/NOT_FOUND cache.
4. P4.20.0-D invoice review integration for authoritative seller id, with legal-name suggestion and explicit Brand mapping confirmation.
5. Signed real-device validation before any merge authorization.
