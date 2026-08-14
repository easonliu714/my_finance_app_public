# Public Governance Canary

This documentation-only file verifies the protected public repository workflow after the clean public re-root.

## Scope

- No production application logic changes.
- No database or schema changes.
- No signing material, API keys, private finance data, receipt images, or private repository history.
- The change is intentionally documentation-only.

## Governance contract under test

1. Changes are made on a non-`main` branch.
2. Pull requests are required before merge.
3. The required GitHub Actions check `Analyze, Test, Build APK` must complete for the pull request head.
4. The pull request branch must be up to date with `main` before merge.
5. Pull request conversations must be resolved before merge.
6. Force pushes and deletion of protected `main` remain disallowed.
7. Public commit identity must use a GitHub noreply email.
8. This canary must not be merged without explicit repository-owner authorization.

## Baseline

- Public root commit: `a8bfdb8df7b2e99f99cab53c9988152abafb5ed4`
- Public root tree: `5fa409ca8475f760330d76467d2fe58022b15c98`
- Public source version: `4.17.2+422`

This canary is a governance-only validation artifact and carries no product behavior change.
