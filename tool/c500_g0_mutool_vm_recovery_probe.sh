#!/usr/bin/env bash
# G0aa: genuine SHA-pinned source, controlled VM failure and fresh-process recovery.
# Never claim PDFBox/PDFium root cause, full Unicode/sorting or global NOT_WIN.
set -euo pipefail
: "$G0_OLD_PDF"
: "$G0_NEW_PDF"
verify() {
  local period="$1" file="$2" size="$3" digest="$4"
  [[ -f "$file" && ! -L "$file" ]] || { echo "G0AA_SOURCE_MISSING_OR_SYMLINK period=$period" >&2; return 65; }
  [[ "$(stat -c %s -- "$file")" == "$size" &&
     "$(sha256sum -- "$file" | cut -d ' ' -f1)" == "$digest" ]] ||
     { echo "G0AA_SOURCE_PIN_MISMATCH period=$period" >&2; return 65; }
  echo "G0AA_SOURCE_PIN_PASS period=$period bytes=$size sha256=$digest"
}
# Both checks must pass BEFORE any mutool execution.
verify 115-05-06 "$G0_OLD_PDF" 119769589 1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe
verify 115-07-08 "$G0_NEW_PDF" 135200798 f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571
[[ "$(readlink -f -- "$G0_OLD_PDF")" != "$(readlink -f -- "$G0_NEW_PDF")" ]] ||
  { echo G0AA_SAME_SOURCE_PATH >&2; exit 65; }
command -v mutool >/dev/null || { echo G0AA_MUTOOL_MISSING >&2; exit 66; }
test -x /usr/bin/time || { echo G0AA_GNU_TIME_MISSING >&2; exit 66; }
tmpdir="$(mktemp -d)"
trap 'rm -rf -- "$tmpdir"' EXIT
echo 'G0AA_SCOPE=CONTROLLED_VM_FAILURE_THEN_FRESH_PROCESS_RECOVERY_NOT_GLOBAL_NOT_WIN'
PROBE_RC=0 PROBE_RSS=UNKNOWN PROBE_BYTES=0 PROBE_SHA=NONE PROBE_ALLOC=NO
probe() {
  local period="$1" file="$2" page="$3" phase="$4" cap="$5" rc=0
  local log="$tmpdir/$period-$phase.log"
  local timing="$tmpdir/$period-$phase.time"
  local out="$tmpdir/$period-$phase.txt"
  (ulimit -v "$cap"; ulimit -f 512;
   timeout --signal=TERM --kill-after=5s 90s \
     /usr/bin/time -f '%M' -o "$timing" \
     mutool draw -F txt -o "$out" "$file" "$page") >"$log" 2>&1 || rc=$?
  PROBE_RC="$rc"
  PROBE_RSS="$(grep -E '^[0-9]+$' "$timing" 2>/dev/null | tail -n 1 || true)"
  [[ -n "$PROBE_RSS" ]] || PROBE_RSS=UNKNOWN
  PROBE_BYTES=0 PROBE_SHA=NONE PROBE_ALLOC=NO
  if grep -Eiq 'bad_alloc|cannot allocate memory|out of memory|memory exhausted|malloc|alloc failed' "$log"; then
    PROBE_ALLOC=YES
  fi
  if [[ "$rc" -eq 0 && -f "$out" ]]; then
    PROBE_BYTES="$(stat -c %s -- "$out")"
    if (( PROBE_BYTES > 0 && PROBE_BYTES <= 524288 )); then
      PROBE_SHA="$(sha256sum -- "$out" | cut -d ' ' -f1)"
    fi
  fi
  echo "G0AA_CASE period=$period page=$page phase=$phase vm_kib=$cap timeout_s=90 output_cap_bytes=524288 exit=$PROBE_RC peak_rss_kib=$PROBE_RSS bytes=$PROBE_BYTES sha256=$PROBE_SHA allocation_diagnostic=$PROBE_ALLOC"
  rm -f -- "$out" "$log" "$timing"
}
case_recovery() {
  local period="$1" file="$2" page="$3" low_rc low_alloc first_sha first_bytes failed=0
  probe "$period" "$file" "$page" low_256m 262144
  low_rc="$PROBE_RC"; low_alloc="$PROBE_ALLOC"
  probe "$period" "$file" "$page" recovery_a_3g 3145728
  first_sha="$PROBE_SHA"; first_bytes="$PROBE_BYTES"
  [[ "$PROBE_RC" -eq 0 && "$first_sha" != NONE ]] || failed=1
  probe "$period" "$file" "$page" recovery_b_3g 3145728
  [[ "$PROBE_RC" -eq 0 && "$PROBE_SHA" != NONE &&
     "$PROBE_SHA" == "$first_sha" && "$PROBE_BYTES" == "$first_bytes" ]] || failed=1
  if [[ "$low_rc" -eq 0 ]]; then
    echo "G0AA_RECOVERY period=$period decision=HOLD_LOW_CAP_DID_NOT_FAIL root_cause=UNKNOWN"
    return 49
  fi
  if (( failed != 0 )); then
    echo "G0AA_RECOVERY period=$period decision=HOLD_HIGH_CAP_OR_REPLAY_FAILED root_cause=UNKNOWN"
    return 49
  fi
  echo "G0AA_RECOVERY period=$period decision=PASS_CAP_ASSOCIATED_FAILURE_THEN_STABLE_RECOVERY low_allocation_diagnostic=$low_alloc root_cause=NOT_ATTRIBUTED_TO_PDFBOX_OR_PDFIUM"
}
failed=0
case_recovery 115-05-06 "$G0_OLD_PDF" 38500 || failed=1
case_recovery 115-07-08 "$G0_NEW_PDF" 43500 || failed=1
if (( failed != 0 )); then
  echo 'G0AA_RESOURCE_RECOVERY=HOLD GLOBAL_NOT_WIN=HOLD'
  exit 49
fi
echo 'G0AA_RESOURCE_RECOVERY=PASS_BOTH_PINNED_PERIODS_CONTROLLED_VM_FAILURE_AND_STABLE_RECOVERY GLOBAL_NOT_WIN=HOLD'
