#!/usr/bin/env bash
# G0z: SHA-pinned official PDFs; bounded MuPDF middle/last random-page feasibility.
# No extracted text is printed, uploaded, or promoted. This is NOT global proof.
set -euo pipefail
: "${G0_OLD_PDF:?G0Z_OLD_SOURCE_MISSING}"
: "${G0_NEW_PDF:?G0Z_NEW_SOURCE_MISSING}"
verify() {
  local period="$1" file="$2" expected_size="$3" expected_sha="$4" actual_size actual_sha
  [[ -f "$file" && ! -L "$file" ]] || { echo "G0Z_SOURCE_MISSING_OR_SYMLINK period=$period" >&2; return 65; }
  actual_size="$(stat -c %s -- "$file")"
  actual_sha="$(sha256sum -- "$file" | cut -d ' ' -f1)"
  [[ "$actual_size" == "$expected_size" && "$actual_sha" == "$expected_sha" ]] || {
    echo "G0Z_SOURCE_PIN_MISMATCH period=$period" >&2; return 65;
  }
  echo "G0Z_SOURCE_PIN_PASS period=$period bytes=$expected_size sha256=$expected_sha"
}
# Both pins must pass before any renderer is invoked.
verify 115-05-06 "$G0_OLD_PDF" 119769589 1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe
verify 115-07-08 "$G0_NEW_PDF" 135200798 f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571
command -v mutool >/dev/null || { echo 'G0Z_MUTOOL_UNAVAILABLE' >&2; exit 66; }
test -x /usr/bin/time || { echo 'G0Z_GNU_TIME_UNAVAILABLE' >&2; exit 66; }
tmpdir="$(mktemp -d)"
trap 'rm -rf -- "$tmpdir"' EXIT
printf '%s\n' 'G0Z_SCOPE=FOUR_RANDOM_PAGE_TEXT_PROBES_ONLY NOT_UNICODE_NOT_SORTED_NOT_COMPLETE_NOT_GLOBAL_NOT_WIN'
probe() {
  local period="$1" file="$2" page="$3" ordinal="$4" rc=0 rss result bytes=0 digest=NONE
  local log="$tmpdir/${period}_${ordinal}.log" timing="$tmpdir/${period}_${ordinal}.time" out="$tmpdir/${period}_${ordinal}.txt"
  # Independent process per page; 3 GiB address space, 512 KiB file, 90 s wall clock.
  (ulimit -v 3145728; ulimit -f 512; timeout --signal=TERM --kill-after=5s 90s /usr/bin/time -f '%M' -o "$timing" mutool draw -F txt -o "$out" "$file" "$page") >"$log" 2>&1 || rc=$?
  rss="$(grep -E '^[0-9]+$' "$timing" 2>/dev/null | tail -n 1 || true)"
  [[ -n "$rss" ]] || rss=UNKNOWN
  result=ENGINE_FAILURE
  if [[ "$rc" -eq 124 || "$rc" -eq 137 ]]; then result=TIME_OR_KILL_BOUND
  elif grep -Eiq 'bad_alloc|cannot allocate memory|out of memory|memory exhausted' "$log"; then result=ALLOCATION_FAILURE
  elif [[ "$rc" -eq 0 ]]; then
    bytes="$(stat -c %s -- "$out")"
    if [[ "$bytes" -gt 0 && "$bytes" -le 524288 ]]; then
      digest="$(sha256sum -- "$out" | cut -d ' ' -f1)"
      result=RANDOM_PAGE_TEXT_NONEMPTY_ONLY
    else result=EMPTY_OR_OVERSIZE_OUTPUT
    fi
  fi
  echo "G0Z_MUTOOL_CASE period=$period ordinal=$ordinal page=$page virtual_kib=3145728 output_max_bytes=524288 timeout_s=90 exit=$rc peak_rss_kib=$rss text_bytes=$bytes text_sha256=$digest result=$result"
  if [[ "$result" != RANDOM_PAGE_TEXT_NONEMPTY_ONLY ]]; then
    sed -n '1,2p' "$log" | cut -c1-160
    return 49
  fi
}
failed=0
probe 115-05-06 "$G0_OLD_PDF" 38500 middle || failed=1
probe 115-05-06 "$G0_OLD_PDF" 77000 last || failed=1
probe 115-07-08 "$G0_NEW_PDF" 43500 middle || failed=1
probe 115-07-08 "$G0_NEW_PDF" 87000 last || failed=1
if (( failed != 0 )); then echo 'G0Z_RANDOM_PAGE_FEASIBILITY=HOLD_FIRST_FAILURE_RECORDED GLOBAL_NOT_WIN=HOLD'; exit 49; fi
echo 'G0Z_RANDOM_PAGE_FEASIBILITY=FOUR_SAMPLES_NONEMPTY_ONLY GLOBAL_NOT_WIN=HOLD'
