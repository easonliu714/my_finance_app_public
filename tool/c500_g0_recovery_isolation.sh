#!/usr/bin/env bash
# G0ad: isolate qpdf XRef recovery from full-graph allocation on BOTH genuine pinned MOF PDFs.
# Each mode runs in a fresh, bounded child; diagnostic metadata only, no PDF bytes in logs.
set -euo pipefail
: "${G0_OLD_PDF:?G0AD_OLD_SOURCE_REQUIRED}"
: "${G0_NEW_PDF:?G0AD_NEW_SOURCE_REQUIRED}"
verify() {
  local period="$1" path="$2" expected_size="$3" expected_sha="$4" size sha
  [[ -f "$path" && ! -L "$path" ]] || { echo "G0AD_SOURCE_MISSING_OR_SYMLINK period=$period" >&2; return 65; }
  size="$(stat -c %s -- "$path")"
  sha="$(sha256sum -- "$path")"; sha="${sha%% *}"
  [[ "$size" == "$expected_size" && "$sha" == "$expected_sha" ]] || {
    echo "G0AD_SOURCE_PIN_MISMATCH period=$period" >&2; return 65;
  }
  echo "G0AD_SOURCE_PIN_PASS period=$period bytes=$size sha256=$sha"
}
verify 115-05-06 "$G0_OLD_PDF" 119769589 1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe
verify 115-07-08 "$G0_NEW_PDF" 135200798 f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571
[[ "$(readlink -f -- "$G0_OLD_PDF")" != "$(readlink -f -- "$G0_NEW_PDF")" ]] || {
  echo G0AD_SAME_SOURCE_PATH >&2; exit 65;
}
command -v qpdf >/dev/null && test -x /usr/bin/time || { echo G0AD_ENGINE_MISSING >&2; exit 66; }
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
echo 'G0AD_SCOPE=QPDF_RECOVERY_DISABLED_VS_DEFAULT VM_3GIB TIME_65S_PER_CHILD GLOBAL_NOT_WIN=HOLD'
G0AD_RESULT=UNKNOWN
probe() {
  local period="$1" file="$2" mode="$3" rc=0 rss result
  local out="$tmp/$period-$mode.out" err="$tmp/$period-$mode.err" timing="$tmp/$period-$mode.time"
  local -a args=(--check)
  if [[ "$mode" == disabled ]]; then args=(--suppress-recovery --check); fi
  (ulimit -v 3145728; ulimit -f 1024; timeout --signal=TERM --kill-after=5s 65s \
    /usr/bin/time -f '%M' -o "$timing" qpdf "${args[@]}" "$file") >"$out" 2>"$err" || rc=$?
  rss="$(grep -E '^[0-9]+$' "$timing" 2>/dev/null | tail -n 1 || true)"
  [[ -n "$rss" ]] || rss=UNKNOWN
  if (( rc == 124 || rc == 137 || rc == 143 )); then result=TIME_OR_KILL_BOUND
  elif grep -Eiq 'std::bad_alloc|cannot allocate memory|out of memory|memory exhausted' "$out" "$err"; then result=ALLOCATION_FAILURE
  elif grep -Eiq 'unrecognized (argument|option)|unknown option|invalid option' "$out" "$err"; then result=OPTION_UNSUPPORTED
  elif (( rc == 0 )); then result=QPDF_STRUCTURE_CHECK_ONLY
  elif (( rc == 153 )); then result=OUTPUT_SIZE_BOUND
  elif grep -Eiq 'cross.reference|xref|damaged|reconstruct|recovery|object stream|file is damaged' "$out" "$err"; then result=STRUCTURE_OR_XREF_FAILURE
  else result=OTHER_NONZERO; fi
  G0AD_RESULT="$result"
  echo "G0AD_CASE period=$period mode=$mode exit=$rc peak_rss_kib=$rss diagnostic_bytes=$(($(stat -c %s "$out") + $(stat -c %s "$err"))) result=$result"
  rm -f -- "$out" "$err" "$timing"
}
compare() {
  local period="$1" file="$2" normal disabled verdict
  probe "$period" "$file" default; normal="$G0AD_RESULT"
  probe "$period" "$file" disabled; disabled="$G0AD_RESULT"
  if [[ "$normal" == ALLOCATION_FAILURE && "$disabled" != ALLOCATION_FAILURE && "$disabled" != OPTION_UNSUPPORTED ]]; then
    verdict=RECOVERY_PATH_DIFFERENCE_SUSPECT_NOT_CAUSAL_PROOF
  elif [[ "$normal" == ALLOCATION_FAILURE && "$disabled" == ALLOCATION_FAILURE ]]; then
    verdict=ALLOCATION_FAILURE_PERSISTS_WITHOUT_RECOVERY
  elif [[ "$disabled" == OPTION_UNSUPPORTED ]]; then verdict=NO_COMPARABLE_RECOVERY_MODE
  else verdict=NO_RECOVERY_CAUSAL_CONCLUSION; fi
  echo "G0AD_PERIOD period=$period default=$normal disabled=$disabled verdict=$verdict GLOBAL_NOT_WIN=HOLD"
}
compare 115-05-06 "$G0_OLD_PDF"
compare 115-07-08 "$G0_NEW_PDF"
echo 'G0AD_RECOVERY_ISOLATION=EVIDENCE_ONLY NO_FULL_PAGE_UNICODE_SORT_OR_NOT_WIN_PROOF'
