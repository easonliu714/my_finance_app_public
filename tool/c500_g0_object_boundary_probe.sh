#!/usr/bin/env bash
# G0ac: independent qpdf/MuPDF first-error-object evidence on BOTH SHA-pinned MOF PDFs.
# One object per period; never claim full Unicode, sortedness or global NOT_WIN.
set -euo pipefail
: "${G0_OLD_PDF:?G0AC_OLD_SOURCE_REQUIRED}"
: "${G0_NEW_PDF:?G0AC_NEW_SOURCE_REQUIRED}"
verify() {
 local period="$1" file="$2" size="$3" sha="$4"
 [[ -f "$file" && ! -L "$file" ]] || { echo "G0AC_SOURCE_MISSING_OR_SYMLINK period=$period" >&2; return 65; }
 [[ "$(stat -c %s -- "$file")" == "$size" && "$(sha256sum -- "$file" | cut -d ' ' -f1)" == "$sha" ]] ||
 { echo "G0AC_SOURCE_PIN_MISMATCH period=$period" >&2; return 65; }
 echo "G0AC_SOURCE_PIN_PASS period=$period bytes=$size sha256=$sha"
}
verify 115-05-06 "$G0_OLD_PDF" 119769589 1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe
verify 115-07-08 "$G0_NEW_PDF" 135200798 f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571
[[ "$(readlink -f -- "$G0_OLD_PDF")" != "$(readlink -f -- "$G0_NEW_PDF")" ]] ||
 { echo G0AC_SAME_SOURCE_PATH >&2; exit 65; }
command -v qpdf >/dev/null && command -v mutool >/dev/null && test -x /usr/bin/time ||
 { echo G0AC_ENGINE_MISSING >&2; exit 66; }
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
echo 'G0AC_SCOPE=FIRST_QPDF_ERROR_OBJECT_ONLY VM_3GIB TIME_45S OUTPUT_4MIB GLOBAL_NOT_WIN=HOLD'
CASE_RESULT=UNKNOWN
probe() {
 local period="$1" file="$2" object="$3" engine="$4" rc=0 rss=UNKNOWN result=UNKNOWN bytes=0 digest=NONE
 local out="$tmp/$period-$engine.out" err="$tmp/$period-$engine.err" timing="$tmp/$period-$engine.time"
 if [[ "$engine" == qpdf ]]; then
 (ulimit -v 3145728; ulimit -f 8192; timeout --signal=TERM --kill-after=5s 45s /usr/bin/time -f '%M' -o "$timing" qpdf "--show-object=$object" "$file") >"$out" 2>"$err" || rc=$?
 else
 (ulimit -v 3145728; ulimit -f 8192; timeout --signal=TERM --kill-after=5s 45s /usr/bin/time -f '%M' -o "$timing" mutool show "$file" "$object") >"$out" 2>"$err" || rc=$?
 fi
 rss="$(grep -E '^[0-9]+$' "$timing" 2>/dev/null | tail -n 1 || true)"; [[ -n "$rss" ]] || rss=UNKNOWN
 bytes="$(stat -c %s -- "$out")"
 if (( rc == 124 || rc == 137 )); then result=TIME_OR_KILL_BOUND
 elif grep -Eiq 'bad_alloc|cannot allocate|out of memory|memory exhausted' "$err"; then result=ALLOCATION_FAILURE
 elif (( rc == 0 && bytes > 0 && bytes <= 4194304 )) && ! grep -Eiq '^(null|error|warning:)' "$out"; then
 result=TARGET_OBJECT_READ_ONLY; digest="$(sha256sum -- "$out" | cut -d ' ' -f1)"
 else result=OBJECT_READ_FAILED_OR_OVERSIZE; fi
 CASE_RESULT="$result"
 echo "G0AC_OBJECT period=$period engine=$engine object=$object exit=$rc peak_rss_kib=$rss bytes=$bytes sha256=$digest result=$result"
 rm -f -- "$out" "$err" "$timing"
}
compare() {
 local period="$1" file="$2" object="$3" q m
 probe "$period" "$file" "$object" qpdf; q="$CASE_RESULT"
 probe "$period" "$file" "$object" mutool; m="$CASE_RESULT"
 if [[ "$q" == TARGET_OBJECT_READ_ONLY && "$m" == TARGET_OBJECT_READ_ONLY ]]; then decision=BOTH_TARGET_OBJECT_READ_ONLY
 elif [[ "$q" != TARGET_OBJECT_READ_ONLY && "$m" == TARGET_OBJECT_READ_ONLY ]]; then decision=QPDF_TARGET_FAILURE_MUPDF_TARGET_RECOVERY_ONLY
 else decision=TARGET_RECOVERY_NOT_PROVEN; fi
 echo "G0AC_PERIOD period=$period decision=$decision CHECK_AND_GLOBAL_NOT_WIN=HOLD"
}
# Real MOF Lab #164 first qpdf --check object-read warnings.
compare 115-05-06 "$G0_OLD_PDF" 4187016
compare 115-07-08 "$G0_NEW_PDF" 4730783
echo 'G0AC_FIRST_ERROR_OBJECT_EXPERIMENT=EVIDENCE_ONLY GLOBAL_NOT_WIN=HOLD'
