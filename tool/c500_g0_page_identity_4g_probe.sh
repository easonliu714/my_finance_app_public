#!/usr/bin/env bash
# G0af: exact-source qpdf full page-ref uniqueness at 4 GiB; no page text.
# New 87K page enumeration failed at 3 GiB in real-source #170.
set -euo pipefail
: "${G0_OLD_PDF:?G0AF_OLD_SOURCE_REQUIRED}"
: "${G0_NEW_PDF:?G0AF_NEW_SOURCE_REQUIRED}"
root="$(cd "$(dirname "$0")/.." && pwd)"
verify() {
  local period="$1" file="$2" size="$3" digest="$4"
  [[ -f "$file" && ! -L "$file" ]] || { echo "G0AF_SOURCE_MISSING_OR_SYMLINK period=$period" >&2; return 65; }
  [[ "$(stat -c %s -- "$file")" == "$size" && "$(sha256sum -- "$file" | cut -d ' ' -f1)" == "$digest" ]] ||
    { echo "G0AF_SOURCE_PIN_MISMATCH period=$period" >&2; return 65; }
  echo "G0AF_SOURCE_PIN_PASS period=$period bytes=$size sha256=$digest"
}
verify 115-05-06 "$G0_OLD_PDF" 119769589 1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe
verify 115-07-08 "$G0_NEW_PDF" 135200798 f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571
[[ "$(readlink -f -- "$G0_OLD_PDF")" != "$(readlink -f -- "$G0_NEW_PDF")" ]] || { echo G0AF_DUPLICATE_SOURCE_PATH >&2; exit 65; }
command -v qpdf >/dev/null && test -x /usr/bin/time && command -v python3 >/dev/null || { echo G0AF_ENGINE_MISSING >&2; exit 66; }
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
probe() {
  local period="$1" file="$2" expected="$3" rc=0 rss=UNKNOWN result=UNKNOWN
  local summary="$tmp/$period.summary" err="$tmp/$period.err" timing="$tmp/$period.time"
  (ulimit -v 4194304; ulimit -f 512; timeout --signal=TERM --kill-after=5s 120s \
    /usr/bin/time -f '%M' -o "$timing" qpdf --show-pages "$file") 2>"$err" |
    python3 "$root/tool/c500_g0_page_identity_stream.py" "$expected" >"$summary" 2>>"$err" || rc=$?
  rss="$(grep -E '^[0-9]+$' "$timing" 2>/dev/null | tail -n 1 || true)"; [[ -n "$rss" ]] || rss=UNKNOWN
  if (( rc == 124 || rc == 137 || rc == 143 )); then result=TIME_OR_KILL_BOUND
  elif grep -Eiq 'std::bad_alloc|cannot allocate memory|out of memory|memory exhausted' "$err"; then result=ALLOCATION_FAILURE
  elif (( rc == 0 )) && grep -Eq "^G0AF_ENUM count=$expected unique_page_refs=$expected identity_sha256=[0-9a-f]{64}$" "$summary"; then
    result=FULL_PAGE_REFERENCE_IDENTITY_ONLY
  else result=ENGINE_OR_IDENTITY_FAILURE; fi
  echo "G0AF_CASE period=$period expected=$expected vm_kib=4194304 exit=$rc peak_rss_kib=$rss result=$result GLOBAL_NOT_WIN=HOLD"
  if [[ "$result" == FULL_PAGE_REFERENCE_IDENTITY_ONLY ]]; then cat "$summary"; fi
}
echo 'G0AF_SCOPE=4GIB_QPDF_FULL_PAGE_REFERENCE_UNIQUENESS_ONLY 120S_EACH NO_TEXT NO_SORTING NO_NOT_WIN'
probe 115-05-06 "$G0_OLD_PDF" 77000
probe 115-07-08 "$G0_NEW_PDF" 87000
echo 'G0AF_DONE=EVIDENCE_ONLY ANDROID_FEASIBILITY=NOT_ESTABLISHED GLOBAL_NOT_WIN=HOLD'
