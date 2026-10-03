# Cloud500 PDF Lab signing key

This key is intentionally **diagnostic-only** and is never used for production
or release signing. It exists solely so successive
`com.easonliu.cloud500diag` APKs can be installed as updates and retain the
Lab's private PDF/cache/log data.

- alias: `cloud500lab`
- certificate SHA-256:
  `51c7fc93ef3d2a04bcd993e6e716b37949efdb74be9af7f48689cfc7ff5c3c53`
- validity: 2026-10-03 .. 2036-09-30

Because this repository is public, this diagnostic key MUST NOT grant any trust
outside the standalone Lab package. Production signing authority remains
completely separate.
