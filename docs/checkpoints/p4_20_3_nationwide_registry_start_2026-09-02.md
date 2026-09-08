# P4.20.3 Nationwide Official Registry — Start Checkpoint

> **SUPERSEDED PRODUCT-DIRECTION NOTE (2026-09-08):**  
> The original 2026-09-02 start plan below required GCIS legal subtype and parent-child closure as part of the main productization path. The owner has since approved a narrower consumer-accounting contract. The current authoritative product-direction document is:
> `docs/p4_20_3_invoice_lookup_registry_product_contract_2026-09-08.md`.
>
> Current rule: FIA `seller_identifier + legal_name` is the nationwide invoice-lookup core. GCIS subtype/parent enrichment is optional metadata refinement and is **not** a P4.20.3 release prerequisite.

## Frozen ancestor

- P4.20.2 package: `4.20.2+455`
- owner-validated exact release authority: `a533c9c87131ee487ca2321f3d53e432121c7981`
- P4.20.2 owner real-device validation: PASS / FROZEN
- Merge Authority: HOLD

P4.20.3 branch starts from the exact owner-validated P4.20.2 commit. P4.20.4 Merchant Decision Composer remains locked until nationwide official data acquisition/install/lookup is closed.

## Current P4.20.3 data architecture

For consumer expense accounting, the official registry is an optional local corroboration dataset keyed by the same 8-digit seller identifier found on invoices.

Current production path:

```text
MOF/FIA BGMOPEN1 nationwide bulk source
→ bounded privacy-reduced staging
→ every valid seller_identifier + legal_name
→ optional subtype/parent metadata
→ deterministic gzip NDJSON + manifest/SHA/provenance
→ bounded transactional handset install / LKG
→ local-only invoice seller lookup
```

GCIS is no longer mandatory for release closure. It may refine legal subtype or parent information but must not trigger full per-seller auditing.

## Merchant identity boundary

Official registered name and consumer MerchantBrand are separate.

Example:

```text
31655572
official: 富達零售股份有限公司晶技門市
consumer MerchantBrand: OK Mart
```

Registry evidence must not silently replace `OK Mart` with the official registered name. This allows consumer-facing expense history to remain stable even when the operating legal entity changes.

## Privacy and accounting boundary

Responsible-person / branch-manager names are excluded from the mobile registry. User-owned MerchantBrand / identity history remains separate from replaceable official registry cache.

Formal transaction boundary remains:

```text
reviewed invoice → TransactionEntrySeed → editable draft → explicit Save → formal transaction
```

## Current release-critical Gates

1. FIA nationwide valid seller-identity pack and deterministic evidence.
2. Canonical Flutter CI.
3. Production distribution manifest/update endpoint.
4. Optional bounded download / stream validation / V23 transactional install.
5. LKG and no-registry fallback.
6. Never-bound seller offline lookup.
7. Invoice Review corroboration + MerchantBrand separation.
8. P4.20.3 version/build + dedicated signed APK.
9. Owner real-device validation.

Legal subtype closure, GCIS full residual acquisition, and full branch-parent closure are not release blockers.
