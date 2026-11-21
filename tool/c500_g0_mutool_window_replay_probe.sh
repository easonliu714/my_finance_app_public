#!/usr/bin/env bash
# G0ab: independent 64-page contiguous window replay on BOTH exact pinned MOF PDFs.
# This is a bounded throughput/determinism feasibility witness, NOT global sorting,
# Unicode correctness, completeness, PDFBox/PDFium root attribution or NOT_WIN.
set -euo pipefail
: "$G0_OLD_PDF"
: "$G0_NEW_PDF"
verify() {
  local period="$1" file="$2" size="$3" digest="$4"
  [[ -f "$file" && ! -L "$file" ]] || { echo "G0AB_SOURCE_MISSING_OR_SYMLINK period=$period" >&2; return 65; }
  [[ "$(stat -c %s -- "$file")" == "$size" &&
     "$(sha256sum -- "$file" | cut -d ' ' -f1)" == "$digest" ]] ||
    { echo "G0AB_SOURCE_PIN_MISMATCH period=$period" >&2; return 65; }
  echo "G0AB_SOURCE_PIN_PASS period=$period bytes=$size sha256=$digest"
}
verify 115-05-06 "$G0_OLD_PDF" 119769589 1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe
verify 115-07-08 "$G0_NEW_PDF" 135200798 f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571
[[ "$(readlink -f -- "$G0_OLD_PDF")" != "$(readlink -f -- "$G0_NEW_PDF")" ]] ||
  { echo G0AB_SAME_SOURCE_PATH >&2; exit 65; }
command -v mutool >/dev/null || { echo G0AB_MUTOOL_MISSING >&2; exit 66; }
test -x /usr/bin/time || { echo G0AB_GNU_TIME_MISSING >&2; exit 66; }
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
echo 'G0AB_SCOPE=64_CONSECUTIVE_PAGES_PER_PERIOD_TWO_FRESH_REPLAYS_NO_GLOBAL_NOT_WIN'
CASE_SHA=NONE CASE_BYTES=0 CASE_RSS=UNKNOWN CASE_RC=49
probe() {
  local period="$1" file="$2" start="$3" phase="$4" end rc=0 count=0 total=0 page size digest
  end=$((start+63))
  local out="$tmp/$period-$phase" log="$tmp/$period-$phase.log" timing="$tmp/$period-$phase.time"
  local manifest="$tmp/$period-$phase.manifest"
  mkdir -p "$out"
  (ulimit -v 3145728; ulimit -f 512;
   timeout --signal=TERM --kill-after=5s 120s /usr/bin/time -f '%M' -o "$timing" mutool draw -F txt -o "$out/page-%d.txt" "$file" "$start-$end") >"$log" 2>&1 || rc=$?
  CASE_RC="$rc"
  CASE_RSS="$(grep -E '^[0-9]+$' "$timing" 2>/dev/null | tail -n 1 || true)"
  [[ -n "$CASE_RSS" ]] || CASE_RSS=UNKNOWN
  CASE_SHA=NONE CASE_BYTES=0
  if (( rc == 0 )); then
    for ((page=start;page<=end;page++)); do
      [[ -f "$out/page-$page.txt" && ! -L "$out/page-$page.txt" ]] || { rc=49; break; }
      size="$(stat -c %s -- "$out/page-$page.txt")"
      if (( size <= 0 || size > 262144 )); then rc=49; break; fi
      total=$((total+size))
      count=$((count+1))
      (cd "$out"; sha256sum -- "page-$page.txt") >> "$manifest"
    done
    [[ "$(find "$out" -maxdepth 1 -type f -name 'page-*.txt' | wc -l)" -eq 64 ]] || rc=49
    (( count == 64 && total <= 16777216 )) || rc=49
    if (( rc == 0 )); then
      CASE_SHA="$(sha256sum -- "$manifest" | cut -d ' ' -f1)"
      CASE_BYTES="$total"
    fi
  fi
  CASE_RC="$rc"
  echo "G0AB_WINDOW period=$period phase=$phase pages=$start-$end expected=64 verified=$count vm_kib=3145728 timeout_s=120 peak_rss_kib=$CASE_RSS exit=$rc total_bytes=$CASE_BYTES manifest_sha256=$CASE_SHA"
  rm -rf -- "$out" "$log" "$timing" "$manifest"
}
check_period() {
  local period="$1" file="$2" start="$3" first_sha first_bytes fail=0
  probe "$period" "$file" "$start" replay_a
  first_sha="$CASE_SHA"; first_bytes="$CASE_BYTES"
  [[ "$CASE_RC" -eq 0 && "$first_sha" != NONE ]] || fail=1
  probe "$period" "$file" "$start" replay_b
  [[ "$CASE_RC" -eq 0 && "$CASE_SHA" == "$first_sha" && "$CASE_BYTES" == "$first_bytes" ]] || fail=1
  if (( fail != 0 )); then
    echo "G0AB_PERIOD period=$period decision=HOLD_WINDOW_OR_REPLAY_FAILED GLOBAL_NOT_WIN=HOLD"
    return 49
  fi
  echo "G0AB_PERIOD period=$period decision=PASS_64_PAGE_WINDOW_DETERMINISTIC_ONLY GLOBAL_NOT_WIN=HOLD"
}
failed=0
check_period 115-05-06 "$G0_OLD_PDF" 38469 || failed=1
check_period 115-07-08 "$G0_NEW_PDF" 43469 || failed=1
if (( failed != 0 )); then echo 'G0AB_REAL_WINDOW_FEASIBILITY=HOLD GLOBAL_NOT_WIN=HOLD'; exit 49; fi
echo 'G0AB_REAL_WINDOW_FEASIBILITY=PASS_128_DISTINCT_PAGES_TWO_INDEPENDENT_REPLAYS GLOBAL_NOT_WIN=HOLD'
