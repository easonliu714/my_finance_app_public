# P4.20.3 Nationwide Official Registry — Start Checkpoint

## Frozen ancestor

- P4.20.2 package: `4.20.2+455`
- owner-validated exact release authority: `a533c9c87131ee487ca2321f3d53e432121c7981`
- P4.20.2 owner real-device validation: PASS / FROZEN
- Merge Authority: HOLD

P4.20.3 branch starts from the exact owner-validated P4.20.2 commit. P4.20.4 Merchant Decision Composer remains locked until nationwide official data acquisition/install/lookup is closed.

## P4.20.3 data architecture

For invoice seller-ID nationwide coverage, the controlled build pipeline uses the Ministry of Finance / Fiscal Information Agency `全國營業(稅籍)登記資料集` as the replayable bulk coverage spine. It is a nationwide active-business dataset keyed by the same 8-digit seller identifier used on invoices and exposes head-office linkage.

GCIS remains the legal-registration enrichment authority for:

- company registration;
- business registration;
- branch registration / parent-company linkage.

Normal handset invoice recognition does not call FIA/GCIS directly. Official sources are acquired by the controlled build/distribution pipeline, privacy-reduced, normalized, hashed, packaged, and installed locally through the P4.20.1 bounded transactional update path.

## Privacy boundary

Mobile registry projection excludes responsible-person / branch-manager names. User-owned MerchantBrand / identity history remains separate from replaceable official registry cache.

## Next Gates

1. Acquire the real nationwide FIA bulk source and freeze source SHA / byte count / row count / acquisition timestamp.
2. Deterministic streaming CSV decode and normalized coverage-spine staging.
3. GCIS company/business/branch enrichment with bounded controlled-build requests and resumable evidence.
4. Resolve duplicate/type/parent-child identity into canonical nationwide entities.
5. Build deterministic gzip NDJSON + manifest + SHA + source date + attribution/license.
6. Publish controlled production endpoint and install through existing bounded transactional updater.
7. Verify seller IDs never previously bound in Merchant DB resolve purely from the nationwide registry.
8. Canonical CI + signed release APK + owner real-device validation.
