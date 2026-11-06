#!/usr/bin/env python3
"""Fail-closed certificate parity for disposable, CI-only C500 release-AOT APKs.

The DER file is exported from the runner's freshly generated debug keystore.
This tool never reads release credentials, signs APKs, or publishes artifacts.
"""

import hashlib
import re
import sys
from pathlib import Path

_APK_CERT_RE = re.compile(
    r"^\s*Signer\s+#(\d+)\s+certificate\s+SHA[- ]?256\s+digest\s*:\s*([0-9a-f]{64})\s*$",
    re.IGNORECASE | re.MULTILINE,
)


class WitnessSignerError(ValueError):
    """A fail-closed, non-sensitive CI certificate validation error."""


def verify_disposable_debug_signer(apksigner_output: str, debug_cert_der: bytes) -> None:
    """Require exactly one APK signer whose cert DER matches the debug key."""
    matches = _APK_CERT_RE.findall(apksigner_output)
    if len(matches) != 1 or matches[0][0] != "1":
        raise WitnessSignerError("HOLD_WITNESS_APK_CERT_PARSE_OR_CARDINALITY")
    if len(debug_cert_der) < 64:
        raise WitnessSignerError("HOLD_WITNESS_DEBUG_CERT_DER_MISSING")
    apk_digest = matches[0][1].lower()
    debug_digest = hashlib.sha256(debug_cert_der).hexdigest()
    if apk_digest != debug_digest:
        raise WitnessSignerError("HOLD_WITNESS_DEBUG_SIGNER_MISMATCH")


def main() -> int:
    if len(sys.argv) != 2:
        print("HOLD_WITNESS_CERT_USAGE", file=sys.stderr)
        return 65
    try:
        cert_der = Path(sys.argv[1]).read_bytes()
        verify_disposable_debug_signer(sys.stdin.read(), cert_der)
    except (OSError, WitnessSignerError) as error:
        marker = (
            str(error)
            if isinstance(error, WitnessSignerError)
            else "HOLD_WITNESS_DEBUG_CERT_DER_UNREADABLE"
        )
        print(marker, file=sys.stderr)
        return 65
    print("C500_WITNESS_DEBUG_SIGNER_MATCH")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
