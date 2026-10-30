#!/usr/bin/env bash
# C500-G0k: synthetic fake stat/sha/qpdf contract, NEVER official PDF evidence.
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/fakebin"
printf 'synthetic old' > "$tmp/old.pdf"
printf 'synthetic new' > "$tmp/new.pdf"
cat > "$tmp/fakebin/stat" <<'MOCK_STAT'
#!/usr/bin/env bash
case "${@: -1}" in
  */old.pdf) echo 119769589 ;;
  */new.pdf) echo 135200798 ;;
  *) exit 70 ;;
esac
MOCK_STAT
cat > "$tmp/fakebin/sha256sum" <<'MOCK_SHA'
#!/usr/bin/env bash
case "${@: -1}" in
  */old.pdf)
    if [[ "${C500_G0K_BAD_SHA_OLD:-0}" == 1 ]]; then printf 'bad'; else printf '1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe'; fi ;;
  */new.pdf) printf 'f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571' ;;
  *) exit 71 ;;
esac
printf '  %s\n' "${@: -1}"
MOCK_SHA
cat > "$tmp/fakebin/qpdf" <<'MOCK_QPDF'
#!/usr/bin/env bash
if [[ "$1" == --version ]]; then echo 'qpdf mock 0.0'; exit 0; fi
printf '%s\n' "$*" >> "$C500_G0K_TRACE"
if [[ "${C500_G0K_QPDF_FAIL_NEW:-0}" == 1 && "$*" == *new.pdf* ]]; then
  echo 'mock invalid xref' >&2
  exit 2
fi
echo 'mock structural check only'
MOCK_QPDF
chmod +x "$tmp/fakebin/"*
export G0_OLD_PDF="$tmp/old.pdf" G0_NEW_PDF="$tmp/new.pdf" C500_G0K_TRACE="$tmp/trace"
PATH="$tmp/fakebin:$PATH" bash "$script_dir/c500_g0_qpdf_preflight.sh" > "$tmp/pass" 2>&1
grep -Fq 'C500_G0K_BOTH_QPDF_STRUCTURE_CHECKS_PASS_NOT_ANDROID_OR_GLOBAL_NEGATIVE' "$tmp/pass"
[[ "$(grep -c '^--check ' "$tmp/trace")" == 2 ]]
: > "$tmp/trace"
if C500_G0K_QPDF_FAIL_NEW=1 PATH="$tmp/fakebin:$PATH" bash "$script_dir/c500_g0_qpdf_preflight.sh" > "$tmp/fail" 2>&1; then
  echo 'C500_G0K_EXPECTED_QPDF_FAILURE' >&2; exit 72
fi
grep -Fq 'C500_G0K_QPDF_CHECK_PASS period=115-05-06' "$tmp/fail"
grep -Fq 'C500_G0K_QPDF_CHECK_FAILED period=115-07-08' "$tmp/fail"
[[ "$(grep -c '^--check ' "$tmp/trace")" == 2 ]]
: > "$tmp/trace"
if C500_G0K_BAD_SHA_OLD=1 PATH="$tmp/fakebin:$PATH" bash "$script_dir/c500_g0_qpdf_preflight.sh" > "$tmp/bad-pin" 2>&1; then
  echo 'C500_G0K_EXPECTED_SOURCE_REJECTION' >&2; exit 73
fi
grep -Fq 'C500_G0K_SOURCE_PIN_MISMATCH period=115-05-06' "$tmp/bad-pin"
[[ ! -s "$tmp/trace" ]]
if G0_OLD_PDF="$tmp/missing.pdf" PATH="$tmp/fakebin:$PATH" bash "$script_dir/c500_g0_qpdf_preflight.sh" > "$tmp/missing" 2>&1; then
  echo 'C500_G0K_EXPECTED_MISSING_SOURCE_REJECTION' >&2; exit 74
fi
grep -Fq 'C500_G0K_SOURCE_MISSING_OR_SYMLINK period=115-05-06' "$tmp/missing"
echo 'PASS C500_G0K_MOCK_TWO_PERIODS_QPDF_FAILURE_AND_SOURCE_PIN_FAIL_CLOSED'
