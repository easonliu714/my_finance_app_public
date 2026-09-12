# P4.20.3 Gate D — Official legal-registration dataset authority

Status: **CONTROLLED BUILD AUTHORITY / PRIVACY-REDUCED PROJECTION ONLY**

This contract records the official legal-registration evidence allowed to enrich the residual FIA nationwide tax-registration queue. It does **not** authorize per-invoice network calls from the handset and it does **not** allow responsible-person / representative / manager fields into the mobile registry.

## Authority rules

1. The Ministry of Finance / FIA `全國營業(稅籍)登記資料集` remains the replayable nationwide seller-ID coverage spine.
2. Ministry of Economic Affairs / Administration of Commerce open-data resources may provide legal-registration corroboration for Company / Business / Branch identity.
3. Only these privacy-reduced facts may enter the Gate-D reconciliation stream:
   - `seller_identifier`
   - `entity_type` (`company`, `business`, `branch`)
   - `legal_name`
   - `registration_status`
   - `parent_seller_identifier` (branch only)
   - `source_dataset`
4. Source datasets may contain privacy-bearing fields such as responsible-person names. Those fields are build-side source data only and MUST NOT be accepted or serialized by the mobile projection.
5. Names never infer entity type. Entity type must come from the governed source class / dataset contract.
6. Branch rows require an authoritative parent seller identifier. A branch without a parent, a non-branch with a parent, or FIA/GCIS parent disagreement is HOLD.
7. Missing legal evidence remains unresolved. Duplicate rows collapse only when canonical legal facts agree.
8. Normal handset invoice recognition MUST NOT call GCIS/data.gov.tw per invoice.

## Verified official open-data evidence (2026-09-02)

The Taiwan Government Open Data Platform identifies the Ministry of Economic Affairs Administration of Commerce (`經濟部商業發展署`) as provider and `政府資料開放授權條款-第1版` as the license for relevant legal-registration datasets.

### Company

Representative company-registration datasets expose `統一編號`, `公司名稱`, company status and production date, are updated monthly, and are provided by `經濟部商業發展署` under `政府資料開放授權條款-第1版`.

Authority class: `company`.

### Business

Representative business-registration datasets expose `統一編號`, `商業名稱`, `商業地址`, `登記狀態`, are updated monthly, and are provided by `經濟部商業發展署` under `政府資料開放授權條款-第1版`.

Authority class: `business`.

### Branch

The official `全國5大超商資料集` demonstrates the governed branch schema: `公司統一編號`, `公司名稱`, `分公司統一編號`, `分公司名稱`, `分公司地址`, `分公司狀態`, and branch dates. It is updated monthly and is provided by `經濟部商業發展署` under `政府資料開放授權條款-第1版`.

Authority class: `branch`; `公司統一編號` is the authoritative parent identifier and `分公司統一編號` is the seller identifier.

This dataset is schema/authority evidence only; because it covers five major chains it MUST NOT be represented as nationwide branch coverage.

## Provenance identifiers

- Government Open Data dataset 22175 — company registration example (`公司登記(依營業項目別)－餐廳餐館`)
- Government Open Data dataset 108372 — business registration example (`商業登記(依營業項目別)－資料處理服務`)
- Government Open Data dataset 32086 — branch schema example (`全國5大超商資料集`)

## Remaining closure

This authority contract does not by itself close Gate D. The next step is to build a reproducible controlled-build acquisition/normalization path for the residual FIA seller identifiers and run those records through `tool/p4_20_3_reconcile_legal_enrichment.py`, preserving source date, source URL/dataset identifier, license and payload SHA evidence.
