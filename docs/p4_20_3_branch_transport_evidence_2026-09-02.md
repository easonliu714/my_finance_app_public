# P4.20.3 Gate D — Official Branch Transport Evidence

Status: PASS / evidence frozen for the exact source artifact observed on 2026-09-02.

This file records the real-data result of the `P4.20.3 Legal Dataset Normalizer` branch transport/schema canary. It is evidence for transport/schema and parent-child integrity only. It does **not** claim nationwide branch coverage and does not replace the FIA nationwide seller spine.

## Authority boundary

- Dataset metadata: `https://data.gov.tw/dataset/32086`
- Source URL: `https://data.gcis.nat.gov.tw/od/file?oid=C054F05C-0A6B-428C-B388-288BDB0618E4`
- Coverage: `five_major_convenience_store_chains_only`
- Nationwide branch coverage claimed: `false`
- FIA head-office identifier automatically implies GCIS legal branch: `false`
- License: `政府資料開放授權條款-第1版`

## Exact observed source evidence

- Exact PR head executing the canary: `fee2f601cf81a1055f6d2c994c64b67a4e72db47`
- Workflow: `P4.20.3 Legal Dataset Normalizer`
- Run: `33622636852` / run number `5`
- Result: `SUCCESS`
- Artifact ID: `9843504986`
- Artifact digest: `sha256:4a8e7f6f9a66795a13653829736075a386773276d7b27e6f4248578ab27752a3`
- Source bytes: `3,673,678`
- Source file SHA-256: `55e42b3c34e9a55a875a1110aa2cfc379eb9e06f251d1fc7a92610a443d9ebab`
- Decoding: `utf-8-sig`
- Source rows: `22,731`
- Valid authoritative parent-child links: `22,730`
- Invalid links: `1`
- Valid-link ratio: `0.9999560072148168`

## Observed schema

The exact downloaded source exposed these columns:

- `公司統一編號`
- `公司名稱`
- `分公司統一編號`
- `分公司名稱`
- `分公司地址`
- `分公司狀態`
- `分公司核准設立日期`
- `分公司最後核准變更日期`

The mobile/privacy-reduced projection remains restricted to:

- `seller_identifier`
- `entity_type`
- `legal_name`
- `registration_status`
- `parent_seller_identifier`
- `source_dataset`

Address and any other non-required source fields are not projected.

## Parent distribution

- `16740494`: `1,553`
- `22555003`: `10,469`
- `22853565`: `1,740`
- `23060248`: `5,911`
- `23285582`: `3,058`
- Unexpected parent identifiers: `0`

## Fail-closed anomaly

One source row had a malformed seven-digit branch identifier:

- source row: `22,166`
- parent seller identifier: `23285582`
- raw normalized branch identifier digits: `8495757`
- branch name present: `true`

Contract: **do not left-pad, infer, repair, or otherwise guess this identifier**. An official registry identifier that is not exactly eight digits remains rejected/HOLD evidence until an authoritative source provides an exact eight-digit identity. This prevents accidentally converting one legal entity into another by heuristic normalization.

## Deterministic privacy-reduced probe

The canary selected the lexicographically first valid branch record after validation:

```json
{"seller_identifier":"00000151","entity_type":"branch","legal_name":"嘉義市第一二○分公司","registration_status":"01","parent_seller_identifier":"23060248","source_dataset":"data.gov.tw:32086"}
```

## Gate consequence

This closes the branch source **transport/schema canary** for the observed source SHA. It proves that controlled-build ingestion can preserve explicit company→branch parent-child identity without responsible-person payload or name inference. It does not close nationwide legal enrichment, final nationwide pack generation, distribution/install, unseen-seller lookup, signed release, or owner real-device validation.

Next unique action: acquire/normalize real Company and Business legal-registration sources and reconcile them against the FIA residual cohort, while keeping this Branch dataset scoped only to its actual five-chain coverage.