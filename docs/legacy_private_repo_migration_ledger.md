# Legacy private repository migration ledger

Date: 2026-08-18

## Purpose

This document preserves the disposition of open planning metadata that existed in the legacy private repository `easonliu714/my_finance_app` when the sanitized public repository became authoritative.

The public source tree was bootstrapped from the sanitized `4.17.2+422` state and subsequently advanced through public P4.17.4. Historical private pull requests are therefore not automatically pending public work.

Rules used for this migration:

- migrate only still-valid product/backlog intent;
- rewrite residual scope when part of the old issue is already implemented;
- consolidate duplicate/overlapping issues;
- do not recreate historical implementation PRs whose code is already represented or superseded by public `main`;
- do not treat old phase/version text as current authority;
- keep current P4.18 invoice work under public PR #3 rather than recreating older invoice-roadmap children.

## Legacy open issues

| Legacy private issue | Disposition | Public authority / reason |
|---|---|---|
| #16 | RESIDUAL_MIGRATED | public #4 — account browsing statistics/grouped UX only; completed credit-card/loan model work excluded |
| #85 | CONSOLIDATED | public #5 — account/merchant selector favorites and grouping |
| #86 | CONSOLIDATED | public #5 |
| #93 | RESIDUAL_MIGRATED | public #6 — pending debit settlement only; existing shared-funds/available-balance foundations retained |
| #94 | MIGRATED | public #7 — loan prepayment simulation/re-estimation |
| #98 | CONSOLIDATED | public #8 — global notification display preferences |
| #113 | RESIDUAL_MIGRATED | public #9 — reload/auto-reload residual; existing low-balance foundations retained |
| #114 | CONSOLIDATED | public #10 — transaction-entry quick-add |
| #117 | CONSOLIDATED | public #8 |
| #334 | SUPERSEDED | review-first candidate/draft architecture is already represented by later production implementation and current P4.18 flow |
| #366 | HISTORICAL_ONLY | APK validation findings record; not an active public backlog item |
| #371 | MIGRATED | public #11 — deterministic time-based default expense category |
| #376 | RESIDUAL_MIGRATED | public #12 — remaining Settings Center / Places / quota/general-settings scope; existing Gemini BYOK is not reset |
| #380 | MIGRATED | public #13 — invoice award-check shortcut/reminder |
| #383 | MIGRATED | public #14 — customizable Home shortcuts |
| #384 | UPDATED_MIGRATION | public #15 — public CI minutes/cache/artifact-storage governance |
| #405 | CONSOLIDATED | public #10 |
| #412 | POLICY_TO_DOCUMENTATION | development/CI governance belongs in repository governance documentation, not a product backlog issue |
| #588 | MIGRATED | public #16 — product-photo + Gemini Vision review-first roadmap |
| #589 | CURRENT_WORK_SUPERSEDES | current public PR #3 owns the active invoice OCR/Gemini review work; create only a residual follow-up after P4.18 closure if needed |
| #590 | MIGRATED | public #18 — final schema freeze / backup audit / local DB encryption |
| #608 | MIGRATED | public #19 — official Taiwan business-calendar annual update/manual CSV fallback |
| #617 | MIGRATED | public #20 — merchant identity history/legal-name changes/local learning |
| #665 | SUPERSEDED | P4.15.2 recognition child was superseded by P4.16/P4.17/P4.18 production work |
| #666 | MIGRATED | public #17 — product image crop/photo-retention child roadmap |
| #667 | RESIDUAL_CONSOLIDATED | public #12 — existing Gemini BYOK/model validation is already implemented; only remaining settings scope migrated |
| #690 | SUPERSEDED | live camera invoice workspace direction is represented by later P4.17 production implementation |
| #691 | RESOLVED_HISTORICAL | Android OCR runtime blocker was repaired before the public baseline |
| #693 | COMPLETED_PREREQUISITE | standalone Invoice Vision Lab served its integration prerequisite and is not a current product backlog item |

## Legacy open pull requests

None of the seven legacy open PRs are recreated in the public repository.

| Legacy private PR | Disposition | Reason |
|---|---|---|
| #694 P4.16 Invoice Vision Lab standalone app | HISTORICAL_NO_MIGRATION | integration prerequisite; later production source supersedes it |
| #695 P4.16 production invoice vision integration | HISTORICAL_NO_MIGRATION | public source contains later production lineage |
| #697 P4.17 Live adaptive evidence overlay | HISTORICAL_NO_MIGRATION | superseded by later P4.17.x/public baseline |
| #699 P4.17.1 Live overlay physical hotfix | HISTORICAL_NO_MIGRATION | superseded by later P4.17.x/public baseline |
| #701 P4.17.2 electronic-wide/traditional-narrow capture profile | HISTORICAL_NO_MIGRATION | sanitized public bootstrap begins at the 4.17.2 generation |
| #704 P4.17.2 Electronic-wide/Traditional-first gate | HISTORICAL_NO_MIGRATION | stacked historical implementation branch |
| #706 Security: prepare public CI and signing boundary | TRANSITION_COMPLETE | existed to prepare the private-to-public transition; public repository is already authoritative |

## Public authority checkpoints

- sanitized public bootstrap: `a8bfdb8df7b2e99f99cab53c9988152abafb5ed4` (`4.17.2+422` generation)
- public P4.17.4 merge: `3c9b9643b4ece0d5bafc568d291c808086b13a9f`
- current invoice hardening: public PR #3, Draft / Unmerged until exact-head CI + signed-device gates + explicit owner merge authorization

## Deletion gate for the legacy private repository

Do not delete the legacy private repository until all of the following are true:

1. this ledger is merged into public `main`;
2. public issues #4–#20 remain accessible and accurately represent the intended residual backlog;
3. legacy Actions artifacts/caches/APK storage has been deleted or explicitly accepted as expiring naturally;
4. any quarantine repositories have separately passed their deletion review;
5. no required source-only material remains exclusively in the legacy repository.

Deleting the legacy repository must not be used as the mechanism for resolving current public PR #3 or any public roadmap issue.