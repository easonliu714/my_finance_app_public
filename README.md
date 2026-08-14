# My Finance App

Local-first personal finance and invoice-assistance app for Taiwan daily accounting.

## Public snapshot

This repository starts from the validated P4.17.2 application source:

- App version: `4.17.2+422`
- Private validation source head: `80ad1aa635b1e87ed4eaffb8e307e0160af8c32a`
- Public history: intentionally re-rooted from a reviewed source snapshot; private development history, old CI artifacts, and private repository secrets are not mirrored here.

## Security boundary

- User finance data remains local-first.
- No Android release signing key or password is committed to this repository.
- Pull-request CI has no release-signing capability.
- Public CI is limited to analyze, tests, and debug build verification.
- Release signing is managed separately through a trusted/manual deployment path.
- Debug artifacts are opt-in and retained for one day.

See `docs/public_release_signing_security.md` for the non-secret release certificate baseline.

## Main capabilities

- Income / expense / transfer accounting
- Account and credit-card workflows
- Installment and repayment flows
- Local backup / restore and migration support
- Manual and assisted invoice entry
- QR / OCR based invoice assistance with explicit review boundaries
- Optional compile-time-gated private cloud-invoice LAB workflow
- Local-first SQLite persistence

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

## Privacy note

The public repository contains source code and synthetic/redacted test fixtures only. It does not intentionally include personal finance databases, receipt images, APK files, keystores, API keys, private repository history, or historical Actions artifacts.

## License

No software license is granted by this repository unless a `LICENSE` file is added later.
