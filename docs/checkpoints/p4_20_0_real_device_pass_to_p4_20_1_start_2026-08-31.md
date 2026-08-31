# P4.20.0 Real-device PASS → P4.20.1 Start

Date: 2026-08-31

## Frozen owner-validated authority

- Package: `4.20.0+453`
- Exact head: `64581aa0d5c322bee8a487f9fd9f0a9d4306b35e`
- PR #38: Draft / OPEN / NOT MERGED
- Flutter Android CI #313: PASS
- P4.20.0 Signed Canary #2: PASS
- Owner real-device validation: PASS
- Merge authority: HOLD

Returned owner screenshots confirmed:
- Android app version 4.20.0;
- existing merchant and seller identifier `30340553` preserved;
- official legal-name corroboration is separately labeled and does not overwrite invoice merchant text;
- official data source is explicitly labeled `P4.20 實機驗證子集`;
- existing merchant selector remains usable;
- manual edit invalidates prior handoff authority;
- AI field selection remains behind the global Local/AI acknowledgement gate;
- duplicate invoice protection reports that an existing transaction was not added again;
- final transaction creation remains behind explicit Save.

Decision: `P4_20_0_OWNER_REAL_DEVICE_PASS_FROZEN`.

## Why Roadmap #20 remains open

P4.20.0 deliberately validated the local registry/identity runtime with a two-record validation subset. It did not yet productize nationwide registry distribution, freshness, user-controlled update, or unknown-seller refresh.

The official GCIS open-data platform provides company/business/branch data and identifies the Ministry of Economic Affairs Business Administration as the data provider. Normal Android invoice recognition must remain local-first and must not depend on a direct per-invoice GCIS API call.

## P4.20.1 target

Branch: `p4-20-1-registry-production-update`

First gate: `P4.20.1-A Nationwide Distribution Contract`.

The nationwide pack must not reuse the validation subset's in-memory JSON-list loading strategy. Million-row official data requires a bounded streaming format:

`controlled builder → deterministic gzip NDJSON → manifest/size/SHA → bounded download → stream validation → transactional install → last-known-good`

The first contract therefore requires:
- nationwide-only production manifests;
- distribution through an app-controlled, allowlisted release endpoint rather than direct GCIS per-invoice requests;
- government attribution and license metadata;
- compressed/uncompressed size ceilings;
- download SHA-256 and registry-content SHA-256;
- exact stream-header binding to manifest authority;
- company/business/branch entity preservation;
- zero responsible-person/personal fields in the mobile canonical entity model.

Later P4.20.1 gates will add the canonical builder, bounded downloader, two-pass stream validation/install, Settings UI (`更新公司行號資料`), installed version/data-date display, freshness policy, unknown seller-ID at-most-one refresh, and signed device validation.

## Safety invariants

- Existing P4.20.0 owner-validated behavior remains frozen.
- Registry replacement must never delete user-owned merchant learning/history.
- Registry lookup/enrichment does not create a formal transaction.
- Accounting write boundary remains:
  `review → TransactionEntrySeed → editable draft → explicit Save → formal transaction`.
- No merge without explicit owner authorization.
