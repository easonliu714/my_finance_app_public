# P4.20.3 Nationwide Official Registry — Invoice-Lookup Product Contract

Status: **OWNER APPROVED / ACTIVE PRODUCT CONTRACT**  
Decision date: **2026-09-08 (Asia/Taipei)**  
PR: **#41** / branch `p4-20-3-nationwide-official-registry`  
Merge Authority: **HOLD**  
P4.20.4 Merchant Decision Composer: **LOCKED until P4.20.3 real-device closure**

## 1. Product objective

P4.20.3 is a consumer expense-accounting feature, not a government-registry auditing product.

The nationwide official registry exists to answer one primary local/offline question after an invoice parser has produced an authoritative seller identifier:

```text
invoice sellerTaxId
        ↓ exact local lookup
official seller identity
        ↓
official legal/business registration name candidate
        ↓ corroboration only
Invoice Review / Merchant identity decision
```

The two most important official fields are therefore:

1. `seller_identifier` — the 8-digit invoice seller tax identifier;
2. `legal_name` — the official registered business/operator name associated with that identifier.

A valid official identity is release-usable when these two facts are available. Full company/business/branch legal-entity classification is not required for invoice lookup.

## 2. MerchantBrand is deliberately separate from official legal name

The name a consumer expects in expense history is often a retail brand, while the invoice seller is a legal/operator entity.

Example approved during the 2026-09-08 product discussion:

| Layer | Example |
| --- | --- |
| Invoice seller tax ID | `31655572` |
| FIA official registered name | `富達零售股份有限公司晶技門市` |
| Consumer-facing MerchantBrand | `OK Mart` |
| Possible location/outlet interpretation | `晶技門市` |

The accounting UI must not silently replace `MerchantBrand = OK Mart` with the official legal name.

This separation is required because a consumer brand may keep the same public identity while its operating legal entity changes. For example, OK Mart may continue to be the consumer-facing brand even when the registered operator changes. Historical expense grouping should therefore remain attached to the user-facing MerchantBrand rather than being fragmented by legal-operator changes.

Canonical rule:

```text
invoice literal
≠ official legal/registered name
≠ MerchantBrand
```

Official registry data is supporting evidence only.

## 3. FIA nationwide source is the release coverage spine

The Ministry of Finance / Fiscal Information Agency dataset `全國營業(稅籍)登記資料集` / `BGMOPEN1.zip` is the P4.20.3 nationwide coverage spine.

Normal handset invoice recognition must never call FIA or GCIS per invoice.

**Hard runtime boundary:** an Invoice Review local-registry miss returns a local miss. It must not probe the distribution manifest and must not trigger a registry refresh. Dataset download/update is an independent explicit user operation.

Controlled-build flow:

```text
FIA nationwide bulk source
→ bounded privacy-reduced staging
→ valid seller identities
→ deterministic canonical registry
→ gzip NDJSON + manifest/SHA/provenance
→ optional bounded handset download
→ transactional install / LKG
→ local-only sellerTaxId lookup
```

## 3.1 Official-detail lookup in the Registry update UI

Owner decision (2026-09-08): the **官方統編資料更新** surface provides an explicit sellerTaxId search for the complete current FIA public row.

This does **not** expand the accounting transaction schema. The complete official row is stored once in the replaceable Registry cache and queried only from the Registry management/detail surface.

Current FIA detail projection uses the 16 published fields:

- 營業地址
- 統一編號
- 總機構統一編號
- 營業人名稱
- 資本額
- 設立日期
- 組織別名稱
- 使用統一發票
- 行業代號 / 名稱
- 行業代號1 / 名稱1
- 行業代號2 / 名稱2
- 行業代號3 / 名稱3

Storage boundary:

```text
business_registry_entities
  → core seller identity used by invoice corroboration

business_registry_official_details
  → replaceable full FIA row for explicit Registry UI inspection only

transactions / merchant history
  → do not duplicate the 16 FIA fields
```

The detail query is local-only against the installed optional dataset. A query must not trigger a manifest probe or background Registry refresh.

Storage/wire optimization: because the 16-field schema is fixed by this product contract, the nationwide stream stores the values as one fixed-order 16-value array rather than repeating 16 field-name strings in every one of the ~1.7M entity records. The UI reconstructs the named field map using the canonical field order. This reduces optional-dataset storage without coupling any field to accounting transactions.

The first named-object full-detail staging experiment measured **1,250,561,071 uncompressed bytes** for 1,712,864 valid identities, exceeding the existing 1 GiB bounded-install ceiling. The fixed-order array representation is therefore a required storage optimization, not a relaxation of the 16-field detail contract.
## 4. Release-critical vs optional metadata

### Release-critical

- valid 8-digit `seller_identifier`;
- non-empty official `legal_name`;
- official source/provenance;
- deterministic pack SHA and entity count;
- source date/generation evidence;
- bounded transactional install;
- local/offline lookup;
- no-registry and update-failure fallback.

### Optional metadata / quality information

These may be retained when available but are not release blockers:

- `parent_seller_identifier` / FIA total/head-office identifier;
- company/business/branch/unknown subtype;
- organization label;
- uses-uniform-invoice label;
- address;
- parent-chain closure status.

Address can be useful later as a consumption-location corroboration signal, but it is not required to close P4.20.3.

## 5. No mandatory full GCIS audit

GCIS company/business/branch data is optional refinement only.

P4.20.3 must not:

- query GCIS for every FIA seller;
- require every row to be classified as company/business/branch;
- require every parent identifier to be present in the active mobile dataset;
- block release because legal subtype is unknown;
- block release because a parent chain is incomplete;
- infer legal subtype from merchant display-name heuristics.

If FIA provides a valid seller ID and official name but legal subtype is not reliably known, materialize:

```text
entity_type = unknown
```

If FIA provides a valid child seller ID and a parent identifier that is absent from the active dataset, keep the child identity and parent identifier. Record parent resolution as quality metadata; do not delete the child and do not block release.

## 6. Malformed official source rows

A malformed government-source row is accounted for and skipped.

Required relationship:

```text
source_valid_identity_count
= source_row_count - source_invalid_row_count
```

A very small number of malformed source rows must not make the entire nationwide registry unusable.

## 7. Current executable evidence at decision implementation

Exact head evidence before the next CI-fix commit:

`10dc58cedca8bde29e812c7684daaa2b560a4f1a`

P4.20.3 Nationwide Registry Distribution #58:

- source rows: **1,712,865**
- valid official seller identities: **1,712,864**
- source-invalid rows skipped: **1**
- mandatory GCIS enrichment for release: **0**
- subtype `unknown`: **15,759**
- unresolved parent references: **466**
- mobile registry entity count: **1,712,864**
- mobile artifact SHA-256: `a1d85a805cc68c5159bda8280313e1709baed9058881f9b9a336015ed5135e8c`
- `source_valid_identity_coverage_complete=true`
- `final_mobile_registry=true`
- artifact ID: **10052395524**

The 15,759 unknown subtype rows and 466 unresolved parent references are intentionally retained and are quality metadata, not release blockers.

## 8. Invoice Review safety contract

Registry lookup may:

- corroborate an already-authoritative sellerTaxId;
- provide official legal-name evidence;
- provide optional supporting metadata;
- propose merchant/location candidates.

Registry lookup must not:

- turn weak OCR text into an authoritative sellerTaxId;
- silently overwrite invoice literal text;
- silently overwrite MerchantBrand;
- create a formal transaction;
- mutate user-owned merchant history merely because the registry cache changed.

Formal accounting boundary remains:

```text
reviewed invoice
→ TransactionEntrySeed
→ editable transaction-entry draft
→ explicit Save
→ formal transaction
```

## 9. Optional local dataset behavior

The nationwide registry remains an optional download.

No registry installed:

```text
OCR / QR / AI
→ Invoice Review continues normally
→ no official-registry enrichment
```

Registry installed:

```text
authoritative sellerTaxId
→ local/offline registry lookup
→ official legal-name corroboration/candidate
→ Invoice Review
```

Update failure:

- with LKG: retain and use the LKG snapshot;
- without LKG: continue OCR/AI-only;
- Invoice Review is never blocked.

## 10. Remaining P4.20.3 release-critical roadmap

1. **FIA valid-identity nationwide pack** — DATA GATE PASS; retain same-head authority as CI advances.
2. **Canonical Flutter CI** — ACTIVE; validate V24 Registry-detail schema and full regression suite.
3. **Production distribution manifest / endpoint contract** — NEXT.
4. **Optional bounded download + stream validation + V24 transactional install** — NEXT.
5. **LKG + no-registry fallback** — NEXT.
6. **Never-bound offline seller lookup** — prove at least `31655572`, `60282181`, and one additional unseen seller.
7. **Invoice Review / MerchantBrand separation regression** — prove official legal name is corroboration only.
8. **P4.20.3 release version/build**.
9. **Dedicated P4.20.3 signed canary APK** — signer/version/permissions/artifact integrity.
10. **OWNER REAL-DEVICE VALIDATION**.

Only after the same release-authority head closes all product/install/lookup/release gates may the project report:

`READY FOR OWNER REAL-DEVICE VALIDATION`


## 11. Owner real-device Gate failure and P4.20.3+457 endpoint hotfix

Real-device validation of signed version `4.20.3+456` on 2026-09-09 found a packaging/runtime configuration defect:

- the handset still showed the previously installed `p4-20-1-canary...` validation subset dated 2025-06-02;
- the Registry update action was disabled with the UI message that no Registry distribution endpoint was configured;
- seller `31655572` therefore returned no local official detail;
- Registry offline/LKG validation could not proceed because the nationwide P4.20.3 pack had never been installable from that APK.

Root cause: `BusinessRegistryUpdateConfiguration.manifestUrl` defaulted to an empty string and the signed APK build did not inject `BUSINESS_REGISTRY_MANIFEST_URL`.

Approved repair boundary:

1. production code carries the allowlisted P4.20.3 GitHub Release manifest URL as the default;
2. `BUSINESS_REGISTRY_MANIFEST_URL` remains available as an explicit build/test override;
3. Registry download/update remains an explicit user action; adding a default endpoint does **not** enable background Registry network access;
4. Invoice Review remains strictly local-only and must never call this update endpoint;
5. failed updates preserve the existing LKG snapshot;
6. the repair is versioned as `4.20.3+457`; P4.20.4 remains locked for the next planned product phase.

The repaired real-device Gate must prove that an existing P4.20.1 validation subset can be explicitly upgraded to the P4.20.3 nationwide Registry and that `31655572` resolves after installation.

## 12. 2026-09-09 +457 real-device download failure and +458 resilience contract

Owner real-device validation of signed `4.20.3+457` at 2026-09-09 22:13 confirmed the endpoint hotfix itself was effective:

- App version displayed `4.20.3+457`;
- the explicit Registry update button was enabled;
- the UI entered `正在下載並驗證公司行號資料…`;
- the previously installed P4.20.1 validation subset / 2025-06-02 snapshot remained available after failure, confirming LKG fail-safe behavior.

The failure moved to the nationwide release-asset transfer path. The observed error was a transient transport interruption (`ClientException: Connection closed while receiving data`) while receiving `nationwide_registry.ndjson.gz` from GitHub release-assets delivery.

The evidence does **not** prove screen lock as the unique root cause. Automatic screen timeout, manual lock/background suspension, Wi-Fi/5G handoff, CDN interruption, or another transient connection loss are all compatible with the observed transport failure. The +458 repair therefore treats the symptom as a resumable-transfer problem rather than encoding a single-cause assumption.

### +458 release-critical transport contract

Version authority is `4.20.3+458` (`versionName=4.20.3`, Android `versionCode=458`). It is a build/version advance and does not consume P4.20.4.

The explicit Registry update flow must satisfy all of the following:

1. **Stable partial ownership.** The partial path is deterministic for the target `registryVersion` and survives transient transport failure, app restart, and manual retry.
2. **HTTP Range resume.** For `0 < partial_size < manifest.compressed_size`, retry requests use `Range: bytes=<partial_size>-`. A resume is accepted only with a semantically correct `206` and matching `Content-Range` start/total. If the server ignores Range and returns `200`, the client must safely truncate and restart from zero rather than append duplicate bytes.
3. **Bounded retry.** Recognized transient transport failures receive a finite retry/backoff budget. Each retry resumes from bytes already durably written. Infinite retry is prohibited.
4. **Integrity remains fail-closed.** Manifest mismatch, invalid Range semantics, exact-size failure, or final SHA-256 mismatch invalidate the candidate and delete the partial. A retained partial is never treated as a verified artifact.
5. **Transactional install / LKG.** Only a fully downloaded, exact-size, SHA-verified and stream-validated artifact may enter V24 transactional installation. Any download/validation/install failure preserves the currently installed snapshot. Authority switches only after successful post-install readback.
6. **Progress authority.** UI stages are: `讀取 manifest → 下載 Registry → SHA/stream 驗證 → V24 transactional install → authority readback/切換完成`. Download progress exposes downloaded MB / total MB, percentage, rolling speed, ETA, retry attempt, and resume offset. Validation/install stages may be stage-only when finer progress would compromise bounded streaming.
7. **Screen-awake aid.** The existing `wakelock_plus` dependency is used only during the explicit update Future to reduce automatic screen-sleep risk, with `finally` release. Manual lock/system suspension can still interrupt the foreground Future; retained partial + Range resume is the recovery authority.
8. **Foreground guidance.** The UI states that the update should remain in the foreground and that, after manual lock/system interruption, reopening the App and pressing update again resumes from retained partial bytes when valid.
9. **Safe error UX.** User-visible transport errors must be short and actionable, for example `下載連線中斷；已保留 X MB，可再次按更新續傳。` Long signed GitHub release-asset URLs remain diagnostic-only and must not be rendered in the normal UI.
10. **No background product expansion.** This hotfix does not add WorkManager, Android DownloadManager, background per-invoice refresh, manifest probing from Invoice Review, or any automatic Registry download.

Required focused regressions include transient disconnect → retained partial → Range resume → final SHA PASS; exhausted transient retry → manual retry/resume; server ignores Range → safe restart; bad `Content-Range` → fail closed; final SHA mismatch → partial deletion; monotonic progress + nonnegative ETA; LKG preservation; and user-facing error URL redaction.

The next owner real-device Gate for +458 must verify: App build 458; visible MB/%/MB/s/ETA; complete foreground download; interruption followed by nonzero-byte resume rather than restart; successful local lookup for `31655572` and `60282181`; airplane-mode offline lookup; and LKG retention on failed update.

## 13. 2026-09-10 +458 real-device functional PASS and +459 progress closure

Owner real-device validation of signed `4.20.3+458` confirmed the core nationwide Registry path:

- download telemetry was visible and responsive on 5G (MB / total MB, %, MB/s, ETA);
- the download completed before any screen-lock/background stress was required;
- SHA/stream validation completed successfully;
- V24 transactional installation completed successfully even after switching App screens during processing;
- nationwide official detail lookup passed for `31655572` and `60282181`, including the complete FIA field view;
- the previous P4.20.1 validation subset was replaced only after successful verification/install.

The remaining owner-observed UX gap is not functional correctness: SHA/stream validation and V24 installation can each take materially longer than the download but previously exposed only an indeterminate stage label.

`4.20.3+459` is therefore a narrow presentation/telemetry closure:

1. validation reports processed uncompressed bytes / total bytes, percentage, processing MB/s and ETA;
2. installation reports processed entity rows / total rows, percentage, rows/s and ETA;
3. the Registry card renders a determinate progress bar whenever a stage has measurable progress;
4. telemetry must not change bounded streaming, manifest/SHA authority, SQLite transaction atomicity or LKG rollback;
5. the existing short/redacted update error presentation is wired into My Page so signed GitHub asset URLs never need to be shown to users.

The +458 download/resume implementation is frozen unless new real-device evidence proves a defect. P4.20.4 remains locked until this final P4.20.3 UX closure is owner-validated.
