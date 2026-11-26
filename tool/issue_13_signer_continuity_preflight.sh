#!/usr/bin/env bash
# Independent public release-certificate preflight; no keys, app data, or DB.
set -euo pipefail
pinned='9BA2CA64E4218795A4313EFB8FDC020011DCEAE0C70F6F0614DF28328BBEDEB7'
source_file='docs/public_release_signing_security.md'
# Owner-installed 4.20.37+495 is the immutable upgrade floor. Reject an
# equal/older candidate before the release workflow reaches signing secrets.
# Android's documented maximum versionCode is 2100000000.
owner_installed_version_code=495
version_file='pubspec.yaml'
if [[ ! -f "$version_file" ]]; then
  printf 'SIGNER_UPGRADE_COMPATIBILITY=HOLD_RELEASE_VERSION_MISSING\n' >&2
  exit 1
fi
mapfile -t version_lines < <(grep -E '^version:' "$version_file" || true)
if [[ "${#version_lines[@]}" -ne 1 ]] ||
   [[ ! "${version_lines[0]}" =~ ^version:[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+\+([1-9][0-9]{0,9})$ ]]; then
  printf 'SIGNER_UPGRADE_COMPATIBILITY=HOLD_RELEASE_VERSION_MALFORMED\n' >&2
  exit 1
fi
version_code="${BASH_REMATCH[1]}"
if (( 10#$version_code <= owner_installed_version_code ||
      10#$version_code > 2100000000 )); then
  printf 'SIGNER_UPGRADE_COMPATIBILITY=HOLD_VERSION_CODE_NOT_GREATER_THAN_OWNER_495\n' >&2
  exit 1
fi
printf 'SIGNER_VERSION_CODE_CANDIDATE=%s OWNER_INSTALLED_CODE=%s DEVICE_STILL_REQUIRED\n' "$version_code" "$owner_installed_version_code"

# Owner-approved immutable public signing-document blob; PR-local edits cannot silently re-authorize signing.
canonical_blob='cf18cd2cc990480a440a7659bf042a1a93c5369e'
if [[ ! -f "$source_file" ]]; then
  printf 'SIGNER_UPGRADE_COMPATIBILITY=HOLD_CANONICAL_CERT_AMBIGUOUS\n' >&2
  exit 1
fi
actual_blob="$(git hash-object "$source_file")"
if [[ "$actual_blob" != "$canonical_blob" ]]; then
  printf 'SIGNER_UPGRADE_COMPATIBILITY=HOLD_CANONICAL_DOC_DRIFT\n' >&2
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
