#!/usr/bin/env bash
# C500-G0x: genuine pinned MOF pair, bounded qpdf memory-threshold experiment.
# A completed experiment is evidence, NOT a successful parser or global NOT_WIN.
set -euo pipefail
: "${G0_OLD_PDF:?G0X_OLD_PINNED_SOURCE_REQUIRED}"
: "${G0_NEW_PDF:?G0X_NEW_PINNED_SOURCE_REQUIRED}"

verify() {
  local period="$1" path="$2" expected_size="$3" expected_sha="$4" actual_size actual_sha
  if [[ ! -f "$path" || -L "$path" ]]; then
    echo "C500_G0X_HOLD_SOURCE_MISSING_OR_SYMLINK period=$period" >&2
    return 65
  fi
  actual_size="$(stat -c %s -- "$path")"
  actual_sha="$(sha256sum -- "$path")"
  actual_sha="${actual_sha%% *}"
  if [[ "$actual_size" != "$expected_size" || "$actual_sha" != "$expected_sha" ]]; then
    echo "C500_G0X_HOLD_SOURCE_PIN_MISMATCH period=$period size=$actual_size" >&2
    return 65
  fi
  echo "C500_G0X_SOURCE_PIN_PASS period=$period bytes=$actual_size sha256=$actual_sha"
}
# Both SHA and length identities must pass before invoking any qpdf process.
verify 115-05-06 "$G0_OLD_PDF" 119769589 1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe
verify 115-07-08 "$G0_NEW_PDF" 135200798 f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571
command -v qpdf >/dev/null || { echo "C500_G0X_HOLD_QPDF_UNAVAILABLE" >&2; exit 66; }
test -x /usr/bin/time || { echo "C500_G0X_HOLD_GNU_TIME_UNAVAILABLE" >&2; exit 66; }
qpdf --version | head -n 1
echo "C500_G0X_SCOPE=QPDF_RESOURCE_THRESHOLD_ONLY NOT_UNICODE_NOT_SORTED_NOT_GLOBAL_NOT_WIN"

run_probe() {
  local period="$1" path="$2" expected="$3" mode="$4" cap="$5"
  local seconds=70 out timing rc=0 rss result observed
  [[ "$mode" == "npages" ]] && seconds=35
  out="$(mktemp)"
  timing="$(mktemp)"
  # Restrict address space and output size independently for each child.
  if [[ "$mode" == "npages" ]]; then
    (ulimit -v "$cap"; ulimit -f 1024; timeout --signal=TERM --kill-after=5s "${seconds}s" /usr/bin/time -f '%M' -o "$timing" qpdf --show-npages "$path") >"$out" 2>&1 || rc=$?
  else
    (ulimit -v "$cap"; ulimit -f 1024; timeout --signal=TERM --kill-after=5s "${seconds}s" /usr/bin/time -f '%M' -o "$timing" qpdf --check "$path") >"$out" 2>&1 || rc=$?
  fi
  rss="$(grep -E '^[0-9]+$' "$timing" | tail -n 1 || true)"
  [[ -n "$rss" ]] || rss=UNKNOWN
  result=NONZERO_OTHER
  if [[ "$rc" -eq 124 || "$rc" -eq 137 ]]; then
    result=TIME_OR_KILL_BOUND
  elif grep -Eiq 'std::bad_alloc|cannot allocate memory|out of memory' "$out"; then
    result=ALLOCATION_FAILURE
  elif [[ "$rc" -eq 0 && "$mode" == "check" ]]; then
    result=STRUCTURE_CHECK_OK_ONLY
  elif [[ "$rc" -eq 0 && "$mode" == "npages" ]]; then
    observed="$(tr -d '\r\n' < "$out")"
    if [[ "$observed" == "$expected" ]]; then
      result=PAGE_COUNT_MATCH_ONLY
    else
      result=PAGE_COUNT_MISMATCH
    fi
  fi
  echo "C500_G0X_RESOURCE_CASE period=$period mode=$mode virtual_kib=$cap timeout_s=$seconds exit=$rc peak_rss_kib=$rss result=$result"
  if [[ "$result" != "PAGE_COUNT_MATCH_ONLY" && "$result" != "STRUCTURE_CHECK_OK_ONLY" ]]; then
    sed -n '1,3p' "$out" | cut -c1-220
  fi
  rm -f -- "$out" "$timing"
}

# Same source and qpdf binary, 1.5-GiB vs 3-GiB virtual memory caps.
# 8 baseline probes plus 2 extra bounded checks; no source files modified.
for cap in 1572864 3145728; do
  run_probe 115-05-06 "$G0_OLD_PDF" 77000 npages "$cap"
  run_probe 115-07-08 "$G0_NEW_PDF" 87000 npages "$cap"
  run_probe 115-05-06 "$G0_OLD_PDF" 77000 check "$cap"
  run_probe 115-07-08 "$G0_NEW_PDF" 87000 check "$cap"
done
# qpdf --check needs more address space than page-count traversal;
# run 4-GiB bounded checks independently to locate its first failure.
for cap in 4194304; do
  run_probe 115-05-06 "$G0_OLD_PDF" 77000 check "$cap"
  run_probe 115-07-08 "$G0_NEW_PDF" 87000 check "$cap"
done
echo "C500_G0X_RESOURCE_LADDER_COMPLETE=EVIDENCE_ONLY G0_GLOBAL_NOT_WIN=HOLD"
