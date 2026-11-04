#!/usr/bin/env bash
# G0ag: full 77K/87K page-to-content graph, source-pinned, 4-GiB desktop only.
set -euo pipefail
: "${G0_OLD_PDF:?G0AG_OLD_SOURCE_REQUIRED}"
: "${G0_NEW_PDF:?G0AG_NEW_SOURCE_REQUIRED}"
root="$(cd "$(dirname "$0")/.." && pwd)"
verify() {
  local period="$1" file="$2" size="$3" sha="$4"
  [[ -f "$file" && ! -L "$file" ]] || { echo "G0AG_SOURCE_MISSING_OR_SYMLINK period=$period" >&2; return 65; }
  [[ "$(stat -c %s -- "$file")" == "$size" && "$(sha256sum -- "$file" | cut -d ' ' -f1)" == "$sha" ]] ||
    { echo "G0AG_SOURCE_PIN_MISMATCH period=$period" >&2; return 65; }
  echo "G0AG_SOURCE_PIN_PASS period=$period bytes=$size sha256=$sha"
}
verify 115-05-06 "$G0_OLD_PDF" 119769589 1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe
verify 115-07-08 "$G0_NEW_PDF" 135200798 f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571
[[ "$(readlink -f -- "$G0_OLD_PDF")" != "$(readlink -f -- "$G0_NEW_PDF")" ]] || { echo G0AG_SAME_SOURCE_PATH >&2; exit 65; }
command -v qpdf >/dev/null && test -x /usr/bin/time && command -v python3 >/dev/null || { echo G0AG_ENGINE_MISSING >&2; exit 66; }
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
probe() {
  local period="$1" file="$2" expected="$3" rc=0 rss=UNKNOWN result=UNKNOWN
  local summary="$tmp/$period.summary" err="$tmp/$period.err" timing="$tmp/$period.time"
  (ulimit -v 4194304; ulimit -f 512;
   timeout --signal=TERM --kill-after=5s 120s /usr/bin/time -f '%M' -o "$timing" qpdf --show-pages "$file") 2>"$err" |
    python3 "$root/tool/c500_g0_page_content_graph_stream.py" "$expected" >"$summary" 2>>"$err" || rc=$?
  rss="$(grep -E '^[0-9]+$' "$timing" 2>/dev/null | tail -n 1 || true)"; [[ -n "$rss" ]] || rss=UNKNOWN
  if (( rc == 124 || rc == 137 || rc == 143 )); then result=TIME_OR_KILL_BOUND
  elif grep -Eiq 'std::bad_alloc|cannot allocate memory|out of memory|memory exhausted' "$err"; then result=ALLOCATION_FAILURE
  elif (( rc == 0 )) && grep -Eq "^G0AG_GRAPH pages=$expected page_refs=$expected content_refs=[0-9]+ graph_sha256=[0-9a-f]{64}$" "$summary"; then
    result=FULL_PAGE_CONTENT_REFERENCE_GRAPH_ONLY
  elif grep -Eq 'G0AG_[A-Z_]+' "$err"; then result=CONTENT_GRAPH_VALIDATION_FAILURE
  else result=ENGINE_OR_OUTPUT_FAILURE; fi
  echo "G0AG_CASE period=$period expected=$expected vm_kib=4194304 timeout_s=120 exit=$rc peak_rss_kib=$rss result=$result GLOBAL_NOT_WIN=HOLD"
  if [[ "$result" == FULL_PAGE_CONTENT_REFERENCE_GRAPH_ONLY ]]; then cat "$summary"; return 0; fi
  grep -oE 'G0AG_[A-Z_]+' "$err" | head -n 1 || true
  return 49
}
echo 'G0AG_SCOPE=ALL_PAGE_CONTENT_REFERENCES_NO_TEXT_NO_SORTING_NO_UNICODE_NO_NOT_WIN'
failed=0
probe 115-05-06 "$G0_OLD_PDF" 77000 || failed=1
probe 115-07-08 "$G0_NEW_PDF" 87000 || failed=1
if (( failed )); then echo 'G0AG_GRAPH_CUSTODY=HOLD_FIRST_FAILURE_RECORDED GLOBAL_NOT_WIN=HOLD'; exit 49; fi
echo 'G0AG_GRAPH_CUSTODY=PASS_REFERENCE_GRAPH_ONLY ANDROID_FEASIBILITY=NOT_ESTABLISHED GLOBAL_NOT_WIN=HOLD'
