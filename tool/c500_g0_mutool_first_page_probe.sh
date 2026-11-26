#!/usr/bin/env bash
# G0y: SHA-pinned official pair, independent MuPDF FIRST-PAGE feasibility only.
set -euo pipefail
: "$G0_OLD_PDF"
: "$G0_NEW_PDF"
verify() {
  local period="$1" file="$2" size="$3" sha="$4" actual_size actual_sha
  [[ -f "$file" && ! -L "$file" ]] || { echo "G0Y_SOURCE_MISSING_OR_SYMLINK $period" >&2; return 65; }
  actual_size="$(stat -c %s -- "$file")"
  actual_sha="$(sha256sum -- "$file" | cut -d ' ' -f1)"
  [[ "$actual_size" == "$size" && "$actual_sha" == "$sha" ]] || { echo "G0Y_SOURCE_PIN_MISMATCH $period" >&2; return 65; }
  echo "G0Y_SOURCE_PIN_PASS period=$period bytes=$size sha256=$sha"
}
verify 115-05-06 "$G0_OLD_PDF" 119769589 1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe
verify 115-07-08 "$G0_NEW_PDF" 135200798 f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571
command -v mutool >/dev/null || { echo "G0Y_MUTOOL_UNAVAILABLE" >&2; exit 66; }
test -x /usr/bin/time
echo "G0Y_SCOPE=FIRST_PAGE_ENGINE_FEASIBILITY_ONLY NOT_UNICODE_NOT_SORTED_NOT_GLOBAL_NOT_WIN"
probe() {
  local period="$1" file="$2" rc=0 rss result bytes=0 digest=NONE
  local log timing out
  log="$(mktemp)"; timing="$(mktemp)"; out="$(mktemp)"
  (ulimit -v 3145728; ulimit -f 512; timeout --signal=TERM --kill-after=5s 90s /usr/bin/time -f '%M' -o "$timing" mutool draw -F txt -o "$out" "$file" 1) >"$log" 2>&1 || rc=$?
  rss="$(grep -E '^[0-9]+$' "$timing" | tail -n 1 || true)"
  [[ -n "$rss" ]] || rss=UNKNOWN
  result=ENGINE_FAILURE
  if [[ "$rc" -eq 124 || "$rc" -eq 137 ]]; then result=TIME_OR_KILL_BOUND
  elif grep -Eiq 'bad_alloc|cannot allocate memory|out of memory|memory exhausted' "$log"; then result=ALLOCATION_FAILURE
  elif [[ "$rc" -eq 0 ]]; then
    bytes="$(stat -c %s -- "$out")"
    if [[ "$bytes" -gt 0 ]]; then
      digest="$(sha256sum -- "$out" | cut -d ' ' -f1)"
      result=FIRST_PAGE_TEXT_NONEMPTY_ONLY
    else result=FIRST_PAGE_TEXT_EMPTY_ONLY
    fi
  fi
  echo "G0Y_MUTOOl_CASE period=$period page=1 virtual_kib=3145728 timeout_s=90 exit=$rc peak_rss_kib=$rss text_bytes=$bytes text_sha256=$digest result=$result"
  if [[ "$result" != FIRST_PAGE_TEXT_NONEMPTY_ONLY ]]; then sed -n '1,2p' "$log" | cut -c1-180; fi
  rm -f -- "$log" "$timing" "$out"
}
probe 115-05-06 "$G0_OLD_PDF"
probe 115-07-08 "$G0_NEW_PDF"
echo "G0Y_SOURCE_PROBE_COMPLETE=EVIDENCE_ONLY GLOBAL_NOT_WIN=HOLD"
