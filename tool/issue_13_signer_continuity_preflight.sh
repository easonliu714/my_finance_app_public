#!/usr/bin/env bash
# Independent public release-certificate preflight; no keys, app data, or DB.
set -euo pipefail
pinned='9BA2CA64E4218795A4313EFB8FDC020011DCEAE0C70F6F0614DF28328BBEDEB7'
source_file='docs/public_release_signing_security.md'
if [[ ! -f "$source_file" ]]; then
  printf 'SIGNER_UPGRADE_COMPATIBILITY=HOLD_CANONICAL_CERT_AMBIGUOUS\n' >&2
  exit 1
fi
mapfile -t canonical_lines < <(grep -E '^([[:xdigit:]]{2}:){31}[[:xdigit:]]{2}$' "$source_file" || true)
if [[ "${#canonical_lines[@]}" -ne 1 ]]; then
  printf 'SIGNER_UPGRADE_COMPATIBILITY=HOLD_CANONICAL_CERT_AMBIGUOUS\n' >&2
  exit 1
fi
canonical="${canonical_lines[0]//:/}"
canonical="${canonical^^}"
if [[ "$pinned" != "$canonical" ]]; then
  printf 'SIGNER_UPGRADE_COMPATIBILITY=HOLD_DOC_PIN_MISMATCH\n' >&2
  exit 1
fi
printf 'SIGNER_UPGRADE_COMPATIBILITY=PIN_PARITY_ONLY_DEVICE_REQUIRED\n'
