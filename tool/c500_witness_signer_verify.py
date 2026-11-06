#!/usr/bin/env python3
"""Fail-closed certificate parity for disposable, CI-only C500 release-AOT APKs.

The DER file is exported from the runner's freshly generated debug keystore.
This tool never reads release credentials, signs APKs, or publishes artifacts.
"""

import hashlib
import re
import sys
from pathlib import Path

# The installed apksigner can report "Signer #1" or "V2 Signer:".
# Require a single explicit certificate line; do not infer signer identity.
_APK_CERT_RE = re.compile(
    r"^\s*(?:Signer\s+#(?P<index>\d+)|V2\s+Signer:)\s+certificate\s+SHA[- ]?256\s+digest\s*:\s*(?P<digest>[0-9a-f]{64})\s*$",
    re.IGNORECASE | re.MULTILINE,
)


class WitnessSignerError(ValueError):
    """A fail-closed, non-sensitive CI certificate validation error."""


def verify_disposable_debug_signer(apksigner_output: str, debug_cert_der: bytes) -> None:
    """Require exactly one APK signer whose cert DER matches the debug key."""
    matches = list(_APK_CERT_RE.finditer(apksigner_output))
    # Extra numbered signer metadata is a HOLD even without its SHA-256 line.
    foreign_signer = re.search(
        r"^\s*Signer\s+#(?!1\b)\d+\s+certificate",
        apksigner_output,
        re.IGNORECASE | re.MULTILINE,
    )
    if (
        len(matches) != 1
        or foreign_signer is not None
        or (matches and matches[0].group("index") not in (None, "1"))
    ):
        # Diagnose the actual apksigner format without logging certificate
        # fingerprints, private keys, or signing credentials. Keep HOLD.
        signer_lines = [
            line.strip()
            for line in apksigner_output.splitlines()
            if re.search(r"\bsigner\b|certificate", line, re.IGNORECASE)
        ]
        shapes = [
            re.sub(r"[0-9a-fA-F]{32,}", "<digest-redacted>", line)[:140]
            for line in signer_lines[:4]
        ]
        raise WitnessSignerError(
            "HOLD_WITNESS_APK_CERT_PARSE_OR_CARDINALITY "
            f"matched={len(matches)} signer_lines={len(signer_lines)} "
            f"line_shapes={shapes!r}"
        )
    if len(debug_cert_der) < 64:
        raise WitnessSignerError("HOLD_WITNESS_DEBUG_CERT_DER_MISSING")
    apk_digest = matches[0].group("digest").lower()
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
