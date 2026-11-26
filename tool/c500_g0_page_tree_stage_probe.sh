#!/usr/bin/env bash
# G0ae: genuine SHA-pinned qpdf root-count vs complete page-dictionary enumeration.
# Streaming ordinal check uses constant memory; no PDF content or page text leaves the lab.
set -euo pipefail
: "${G0_OLD_PDF:?G0AE_OLD_SOURCE_REQUIRED}"
: "${G0_NEW_PDF:?G0AE_NEW_SOURCE_REQUIRED}"
verify() {
  local period="$1" file="$2" bytes="$3" sha="$4"
  [[ -f "$file" && ! -L "$file" ]] || { echo "G0AE_SOURCE_MISSING_OR_SYMLINK period=$period" >&2; return 65; }
  [[ "$(stat -c %s -- "$file")" == "$bytes" && "$(sha256sum -- "$file" | cut -d ' ' -f1)" == "$sha" ]] ||
    { echo "G0AE_SOURCE_PIN_MISMATCH period=$period" >&2; return 65; }
  echo "G0AE_SOURCE_PIN_PASS period=$period bytes=$bytes sha256=$sha"
}
verify 115-05-06 "$G0_OLD_PDF" 119769589 1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe
verify 115-07-08 "$G0_NEW_PDF" 135200798 f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571
[[ "$(readlink -f -- "$G0_OLD_PDF")" != "$(readlink -f -- "$G0_NEW_PDF")" ]] || { echo G0AE_SAME_SOURCE_PATH >&2; exit 65; }
command -v qpdf >/dev/null && test -x /usr/bin/time || { echo G0AE_ENGINE_MISSING >&2; exit 66; }
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
# AWK accepts only consecutive page ordinals and emits a single bounded numeric count.
# No page objects or text are retained, and a partial enumeration is never a PASS.
ordinal_count() {
  awk '
    /^page [0-9]+:/ {
      n=$2; sub(/:$/, "", n)
      if (n != count+1) bad=1
      count++
    }
    END { if (bad || count==0) { print "INVALID"; exit 49 }; print count }
  '
}
probe() {
  local period="$1" file="$2" expected="$3" mode="$4" rc=0 rss=UNKNOWN observed=NONE result
  local out="$tmp/$period-$mode.count" err="$tmp/$period-$mode.err" timing="$tmp/$period-$mode.time"
  if [[ "$mode" == root ]]; then
    (ulimit -v 3145728; ulimit -f 512; timeout --signal=TERM --kill-after=5s 100s \
      /usr/bin/time -f '%M' -o "$timing" qpdf --show-npages "$file") >"$out" 2>"$err" || rc=$?
  else
    (ulimit -v 3145728; ulimit -f 512; timeout --signal=TERM --kill-after=5s 100s \
      /usr/bin/time -f '%M' -o "$timing" qpdf --show-pages "$file") 2>"$err" | ordinal_count >"$out" || rc=$?
  fi
  rss="$(grep -E '^[0-9]+$' "$timing" 2>/dev/null | tail -n 1 || true)"; [[ -n "$rss" ]] || rss=UNKNOWN
  observed="$(cat "$out" 2>/dev/null || true)"; [[ "$observed" =~ ^[0-9]+$ ]] || observed=NONE
  if (( rc == 124 || rc == 137 || rc == 143 )); then result=TIME_OR_KILL_BOUND
  elif grep -Eiq 'std::bad_alloc|cannot allocate memory|out of memory|memory exhausted' "$err"; then result=ALLOCATION_FAILURE
  elif (( rc == 0 )) && [[ "$observed" == "$expected" ]]; then result=EXPECTED_PAGE_COUNT_ONLY
  elif (( rc == 0 )); then result=COUNT_MISMATCH
  else result=ENGINE_OR_ENUMERATION_FAILURE; fi
  echo "G0AE_CASE period=$period mode=$mode expected=$expected observed=$observed exit=$rc peak_rss_kib=$rss result=$result"
  G0AE_RESULT="$result"
}
compare() {
  local period="$1" file="$2" expected="$3" root full
  probe "$period" "$file" "$expected" root; root="$G0AE_RESULT"
  probe "$period" "$file" "$expected" enumerate; full="$G0AE_RESULT"
  local verdict
  if [[ "$root" == EXPECTED_PAGE_COUNT_ONLY && "$full" == EXPECTED_PAGE_COUNT_ONLY ]]; then
    verdict=QPDF_PAGE_DICTIONARY_ENUMERATION_FEASIBLE_NOT_CONTENT_PROOF
  elif [[ "$root" == EXPECTED_PAGE_COUNT_ONLY && "$full" == ALLOCATION_FAILURE ]]; then
    verdict=PAGE_TREE_ENUMERATION_ALLOCATION_BOUNDARY
  elif [[ "$root" == EXPECTED_PAGE_COUNT_ONLY ]]; then
    verdict=PAGE_TREE_ENUMERATION_NOT_ESTABLISHED
  else verdict=ROOT_COUNT_CONTROL_FAILED; fi
  echo "G0AE_PERIOD period=$period root=$root enumerate=$full verdict=$verdict GLOBAL_NOT_WIN=HOLD"
}
echo 'G0AE_SCOPE=QPDF_ROOT_COUNT_VS_PAGE_DICTIONARY_ENUMERATION VM_3GIB TIME_100S_EACH NO_PAGE_TEXT GLOBAL_NOT_WIN=HOLD'
compare 115-05-06 "$G0_OLD_PDF" 77000
compare 115-07-08 "$G0_NEW_PDF" 87000
echo 'G0AE_PAGE_TREE_STAGE=EVIDENCE_ONLY NO_UNICODE_SORTING_CONTENT_OR_GLOBAL_NOT_WIN_PROOF'
