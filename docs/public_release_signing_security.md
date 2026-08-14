# Public Release Signing Security Baseline

## Canonical signing identity

The Android release certificate SHA-256 fingerprint verified from the P4.17.2 signed APK is:

```text
36:1A:08:06:C3:1E:CE:FF:B0:DE:AD:7E:DA:5F:BC:D7:68:84:5D:8A:00:D6:69:B0:23:2B:8C:11:21:0A:ED:1A
```

Validation provenance:

```text
Validated source head: 80ad1aa635b1e87ed4eaffb8e307e0160af8c32a
Validated app version: 4.17.2+422
Signed APK SHA-256: f299d86c42fd9d8325a76e1d57733d37709758f4b8863a0f641aa8bbb87c3b9c
```

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
