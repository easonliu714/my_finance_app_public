# Public Release Signing Security Baseline

## Canonical current public signing identity — Owner-authorized B1/B2 candidate 2026-11-02

Current public 4.20.35+493 installed-version signing lineage (candidate successor 4.20.36+494) has one active SHA-256 certificate fingerprint:

9B:A2:CA:64:E4:21:87:95:A4:31:3E:FB:8F:DC:02:00:11:DC:EA:E0:C7:0F:6F:06:14:DF:28:32:8B:BE:DE:B7

Public independent evidence:
- [PR #24](https://github.com/easonliu714/my_finance_app_public/pull/24): signed 4.19.1+437, 9BA2 signer, APK SHA-256 `2ffa28fa9e0ee9f225c687752be16cce44d15ec634bdd1960d9d978c201276bf`, Owner Android UAT PASS 2026-08-19.
- [PR #41](https://github.com/easonliu714/my_finance_app_public/pull/41) 4.20.3+459 and [PR #42](https://github.com/easonliu714/my_finance_app_public/pull/42) 4.20.4+461: Owner Android UAT PASS (PR42 2026-09-13); public release workflows pin the same 9BA2 signer.
- Exact 4.20.35+493 source `f70fb8ae3f3b93f8b28842336b8d8c8ac9d226c8`: [Flutter CI 38562431249](https://github.com/easonliu714/my_finance_app_public/actions/runs/38562431249) SUCCESS; [Signed Canary 38562441477](https://github.com/easonliu714/my_finance_app_public/actions/runs/38562441477) validation/build/inspect SUCCESS, job `115855008080`, `apksigner verify --print-certs` against 9BA2, versionName 4.20.35/versionCode 493, APK SHA-256 `108d9f77065fbed24e5342fa7f49ec4496cca698dda0fc42fc3a7dd5db65bf63`; artifact `11895631506` expired (historical logs, not a live download).
- Owner 2026-10-14 22:38 Asia/Taipei screenshot/roadmap record and new 2026-11-02 screenshot both confirm installed version `4.20.35+493` (latest registry ID `p4.20.3-fia-2026-09-09-b98874df3998`); Owner authorizes B1 #4/B2 #19 Signed **candidate**. Screenshots do NOT independently expose the installed APK's certificate bytes.
- Source successor `pubspec.yaml` version 4.20.36+494 has versionCode 494 > 493. Exact 493 and 494 Issue #13 release workflows both use `flutter create --platforms=android --no-pub .` and pin 9BA2. Inspect actual packageName/version/certificate/permissions from the new signed artifact before Owner installation.

**Fail-closed boundary:** exact document blob + unique active certificate + workflow pin parity are necessary, not sufficient. The guard must report `SIGNER_UPGRADE_COMPATIBILITY=PIN_PARITY_ONLY_DEVICE_REQUIRED`, never upgrade PASS. No independently established v3 signer rotation, no guarantee that Android accepts an in-place update, and no data-retention UAT yet. If Android rejects install or package/signature differs, HOLD; never uninstall/clear data, bypass signing, touch finance SQLite, or handle private keys.

## Historical P4.17.2+422 private-to-public bootstrap certificate — preserved, not current

Historical certificate `36:1A:08:06:C3:1E:CE:FF:B0:DE:AD:7E:DA:5F:BC:D7:68:84:5D:8A:00:D6:69:B0:23:2B:8C:11:21:0A:ED:1A`, original source `80ad1aa635b1e87ed4eaffb8e307e0160af8c32a`, historical APK SHA-256 `f299d86c42fd9d8325a76e1d57733d37709758f4b8863a0f641aa8bbb87c3b9c`, original security-doc Git blob `9ad40b06762dbc5e9faca37fbc11da0fbdfcf6a9`. The 36:1A signer is retained as historical provenance, not silently equated with 9BA2. No proof of v3 rotation is asserted; a device actually installed with 36:1A is not presumed compatible with 9BA2. Private repository access cutoff 2026-08-18 is documented in the migration ledger.

The certificate fingerprint is public verification material. It is not the private key.

## Secret handling rules

Never commit:

- Android keystores (`*.jks`, `*.keystore`)
- keystore Base64 payloads
- keystore passwords
- key passwords
- `key.properties`
- private-key files
- local finance databases
- production API keys

## Public CI boundary

Public pull-request CI must not reference Android signing secrets or build a signed release APK.

The canonical public CI path is limited to:

- `flutter analyze`
- `flutter test`
- debug build verification
- optional manual debug artifact with one-day retention

Release signing must be isolated from untrusted pull-request execution and restricted to an explicitly trusted deployment path.

## Upgrade continuity gate

A future signed APK is accepted as release-compatible only after all of the following pass:

1. APK signature verification passes.
2. Certificate SHA-256 equals the canonical fingerprint above.
3. APK installs directly over the currently installed release without uninstalling it.
4. Existing app data remains intact after the upgrade.
