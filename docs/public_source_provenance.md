# Public Source Provenance

This repository was intentionally created as a clean public re-root rather than by changing the historical private repository to public visibility.

The source baseline was downloaded from the validated P4.17.2 branch and verified against the Git tree for:

```text
source commit: 80ad1aa635b1e87ed4eaffb8e307e0160af8c32a
source tree:   fe70e6c37e67a4e294b0470b2b05883080685594
version:       4.17.2+422
```

Before publication:

- legacy/private CI workflows were removed;
- normal CI was replaced with a read-only, non-signing public workflow;
- keystore/database/install-artifact ignore rules were added;
- internal phase/device-history documents were not mirrored;
- real-device invoice identifiers in retained tests were pseudonymized;
- the resulting public tree was re-scanned for high-signal credential patterns.

The historical private repository remains the authoritative archive for old PRs, branches, Actions logs, artifacts, and internal development records.
