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

Maintain event-driven project handoff evidence rather than relying on conversation length alone. Important implementation, exact-head CI, signed-device, merge, rollback and governance transitions should be captured in repository/project snapshots so a new conversation can recover without guessing.