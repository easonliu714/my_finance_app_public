#!/usr/bin/env bash
# G0ah: source-pinned 3 x 512 genuine pages per PDF, MuPDF decoded UTF-8 lexical audit.
# Never claim full-source Unicode semantics, complete award list, sorting, Android or NOT_WIN.
set -euo pipefail
: "${G0_OLD_PDF:?G0AH_OLD_SOURCE_REQUIRED}"
: "${G0_NEW_PDF:?G0AH_NEW_SOURCE_REQUIRED}"
root="$(cd "$(dirname "$0")/.." && pwd)"
verify() {
  local period="$1" file="$2" size="$3" sha="$4"
  [[ -f "$file" && ! -L "$file" ]] || { echo "G0AH_SOURCE_MISSING_OR_SYMLINK period=$period" >&2; return 65; }
  [[ "$(stat -c %s -- "$file")" == "$size" && "$(sha256sum -- "$file" | cut -d ' ' -f1)" == "$sha" ]] ||
    { echo "G0AH_SOURCE_PIN_MISMATCH period=$period" >&2; return 65; }
  echo "G0AH_SOURCE_PIN_PASS period=$period bytes=$size sha256=$sha"
}
verify 115-05-06 "$G0_OLD_PDF" 119769589 1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe
verify 115-07-08 "$G0_NEW_PDF" 135200798 f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571
[[ "$(readlink -f -- "$G0_OLD_PDF")" != "$(readlink -f -- "$G0_NEW_PDF")" ]] || { echo G0AH_SAME_SOURCE_PATH >&2; exit 65; }
command -v mutool >/dev/null && command -v python3 >/dev/null && test -x /usr/bin/time || { echo G0AH_ENGINE_MISSING >&2; exit 66; }
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
probe() {
  # Bash local assignments expand before start is initialized under set -u.
  local period="$1" file="$2" start="$3" label="$4"
  local end=$((start + 511)) rc=0 rss=UNKNOWN
  local out="$tmp/$period-$label" log="$tmp/$period-$label.log" timing="$tmp/$period-$label.time" summary="$tmp/$period-$label.summary"
  mkdir -p "$out"
  (ulimit -v 3145728; ulimit -f 512;
   timeout --signal=TERM --kill-after=5s 180s /usr/bin/time -f '%M' -o "$timing" mutool draw -F txt -o "$out/page-%d.txt" "$file" "$start-$end") >"$log" 2>&1 || rc=$?
  rss="$(grep -E '^[0-9]+$' "$timing" 2>/dev/null | tail -n 1 || true)"; [[ -n "$rss" ]] || rss=UNKNOWN
  if (( rc == 0 )); then python3 "$root/tool/c500_g0_decoded_text_window_audit.py" "$out" "$start" 512 >"$summary" 2>>"$log" || rc=$?; fi
  echo "G0AH_CASE period=$period segment=$label pages=$start-$end vm_kib=3145728 timeout_s=180 exit=$rc peak_rss_kib=$rss"
  if (( rc == 0 )); then cat "$summary"; return 0; fi
  # Print a bounded typed audit marker, never source text or engine logs.
  grep -m1 -E '^G0AH_[A-Z_]+( |$)' "$log" | cut -c 1-160 || true
  echo "G0AH_FIRST_FAILURE=ENGINE_OR_TEXT_AUDIT period=$period segment=$label GLOBAL_NOT_WIN=HOLD"
  return 49
}
echo 'G0AH_SCOPE=TRUE_DECODED_TEXT_3072_DISTINCT_OFFICIAL_PAGES_ONLY_NOT_GLOBAL_NOT_WIN'
failed=0
probe 115-05-06 "$G0_OLD_PDF" 1 first || failed=1
probe 115-05-06 "$G0_OLD_PDF" 38245 middle || failed=1
probe 115-05-06 "$G0_OLD_PDF" 76489 last || failed=1
probe 115-07-08 "$G0_NEW_PDF" 1 first || failed=1
probe 115-07-08 "$G0_NEW_PDF" 43245 middle || failed=1
probe 115-07-08 "$G0_NEW_PDF" 86489 last || failed=1
if (( failed )); then echo 'G0AH_TEXT_QUALITY=HOLD_FIRST_FAILURE_RECORDED GLOBAL_NOT_WIN=HOLD'; exit 49; fi
echo 'G0AH_TEXT_QUALITY=PASS_3072_DECODED_UTF8_PAGES_LEXICAL_ONLY GLOBAL_NOT_WIN=HOLD'
