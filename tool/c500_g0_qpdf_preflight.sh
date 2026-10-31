#!/usr/bin/env bash
# C500-G0k: independent bounded qpdf xref/stream check of both pinned MOF PDFs.
# A qpdf success is NOT Android engine success, page completeness, or NOT_WIN.
set -euo pipefail
: "${G0_OLD_PDF:?C500_G0K_OLD_SOURCE_REQUIRED}"
: "${G0_NEW_PDF:?C500_G0K_NEW_SOURCE_REQUIRED}"

verify_source() {
  local period="$1" path="$2" bytes="$3" digest="$4" actual_bytes actual_sha
  if [[ ! -f "$path" || -L "$path" ]]; then
    echo "C500_G0K_SOURCE_MISSING_OR_SYMLINK period=$period" >&2
    return 1
  fi
  actual_bytes="$(stat -c '%s' -- "$path")"
  actual_sha="$(sha256sum -- "$path")"
  actual_sha="${actual_sha%% *}"
  if [[ "$actual_bytes" != "$bytes" || "$actual_sha" != "$digest" ]]; then
    echo "C500_G0K_SOURCE_PIN_MISMATCH period=$period bytes=$actual_bytes" >&2
    return 1
  fi
  echo "C500_G0K_SOURCE_PIN_OK period=$period bytes=$actual_bytes sha256=$actual_sha"
}

# Both identities must pass before either file reaches a third-party parser.
verify_source 115-05-06 "$G0_OLD_PDF" 119769589 \
  1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe
verify_source 115-07-08 "$G0_NEW_PDF" 135200798 \
  f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571
command -v qpdf >/dev/null || { echo 'C500_G0K_QPDF_UNAVAILABLE' >&2; exit 64; }
qpdf --version | head -n 1

check_pdf() {
  local period="$1" path="$2" output rc
  output="$(mktemp)"
  echo "C500_G0K_QPDF_CHECK_BEGIN period=$period memory_virtual_kib=1572864 timeout_seconds=120"
  if (ulimit -v 1572864; timeout --signal=TERM --kill-after=5s 120s qpdf --check "$path") >"$output" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  sed -n '1,24p' "$output" | cut -c1-300
  rm -f -- "$output"
  if [[ "$rc" -eq 0 ]]; then
    echo "C500_G0K_QPDF_CHECK_PASS period=$period STRUCTURE_ONLY_NOT_GLOBAL_NEGATIVE"
  else
    echo "C500_G0K_QPDF_CHECK_FAILED period=$period exit=$rc NOT_PROOF_OF_CORRUPTION" >&2
    return 1
  fi
}

failures=0
check_pdf 115-05-06 "$G0_OLD_PDF" || failures=$((failures + 1))
check_pdf 115-07-08 "$G0_NEW_PDF" || failures=$((failures + 1))
if [[ "$failures" -ne 0 ]]; then
  echo "C500_G0K_HOLD_QPDF_DIAGNOSTIC_FAILURE count=$failures" >&2
  exit 1
fi
echo 'C500_G0K_BOTH_QPDF_STRUCTURE_CHECKS_PASS_NOT_ANDROID_OR_GLOBAL_NEGATIVE'
