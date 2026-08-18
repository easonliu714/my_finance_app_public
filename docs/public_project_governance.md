# Public project governance

Migrated and updated from legacy private issue #412 on 2026-08-18.

## Branch and merge safety

- Never push product changes directly to `main`.
- Runtime, database, migration, formal-write, account, merchant, privacy or release blockers use an isolated reviewed branch/PR.
- Before any merge, verify the PR latest head SHA and successful required CI for that exact SHA.
- Signed/device-gated work remains Draft until the physical gate is complete.
- Never auto-merge; explicit owner merge authorization is required.

## Low-risk train work

Parser-only, docs-only and test-only changes may be accumulated in a short train when doing so reduces CI churn without hiding runtime risk.

- keep trains small and reviewable;
- do not bury runtime/schema/write behavior inside a low-risk train;
- update formal version numbers for a release/device candidate rather than every tiny internal commit.

## GitHub Actions and storage

- PR CI must remain trustworthy; optimization must not skip required runtime tests.
- Debug/release APK artifact upload is opt-in or release-gated where practical.
- Signed validation artifacts use minimal explicit retention; current P4.18 policy is one day.
- Superseded workflow runs may be canceled when safe.
- Track `actions_storage` as GB-hours: retained artifacts/caches continue accumulating usage over time even when no new artifact is created.

## Privacy/release boundary

- Public CI never embeds release credentials in source.
- API keys and user financial data must not appear in source, logs, readable exports or uploaded evidence.
- Image/network upload remains explicit and user-triggered wherever the product contract requires consent.
- OCR/AI review output cannot directly create a formal financial transaction unless a separately reviewed explicit-confirmation flow authorizes that write.

## Session closeout

At the end of an implementation session, state one concrete next action:

- CI/workflow/PR that is still running;
- physical-device gate the owner must perform;
- data/evidence the owner must report;
- or explicitly state that no user action is required.

## Progress handoff

Maintain event-driven project handoff evidence rather than relying on conversation length alone.

### Micro Checkpoint

Create or refresh a lightweight checkpoint immediately after a material transition, including at least:

- exact product version/build;
- `main` SHA, active branch, active PR and exact active head;
- current task/root cause;
- current CI/signed/device state;
- safety/non-regression contracts affected;
- blocker and exact next action.

Typical triggers include:

- product/runtime commit or rollback;
- exact-head CI PASS/FAIL/HOLD;
- Signed APK ready/fail;
- real-device Gate PASS/FAIL/HOLD;
- root-cause reclassification;
- governance/backlog migration decision;
- Phase/Gate transition.

### Milestone Full Snapshot

A downloadable full project snapshot is mandatory at major milestones. Do not wait for the conversation to approach its context limit.

Mandatory snapshot triggers include:

- completion of the legacy private-repo audit/backlog migration;
- PR merge or post-merge production baseline change;
- completion of a real-device validation cycle, PASS or FAIL;
- Signed APK/release candidate becoming ready for owner validation;
- phase/version transition;
- major blocker/root-cause closure;
- substantial governance or safety-policy change;
- before starting a large new implementation phase when recovery risk would increase.

Each full snapshot should preserve:

1. project goal and current phase;
2. repository/branch/PR/exact-SHA authority;
3. app version/build and signed-artifact provenance where applicable;
4. completed and unfinished work;
5. CI/test/device Gate results;
6. user-provided real-device findings that GitHub cannot recover;
7. non-regression and privacy/safety contracts;
8. known risks/HOLD conditions;
9. backlog/governance migration state;
10. exact next action and merge authorization state;
11. new-chat recovery procedure and snapshot staleness check.

Snapshot filenames should be explicit and sortable, for example:

`Finance_App_專案進度快照_v<version>_<milestone>_<YYYY-MM-DD_HHmm>.md`

### Snapshot staleness check

A new conversation must not assume the latest snapshot is technically current. Reconcile snapshot `main_sha` and `active_head` with GitHub first. If they differ, mark the snapshot as stale for technical state, refresh code/CI facts from GitHub, and preserve only the snapshot information GitHub cannot reconstruct such as device findings, decisions, safety rationale and pending manual Gates.

### Current special milestone rule

The current legacy private-repository audit / backlog consolidation is a mandatory milestone. When that task is fully closed, create and provide a Full Snapshot before the old repository authorization is removed or before product work continues beyond the next safe checkpoint.