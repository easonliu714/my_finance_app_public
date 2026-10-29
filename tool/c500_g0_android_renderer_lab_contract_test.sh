#!/usr/bin/env bash
# C500-G0f: hermetic three-engine shell regression. Synthetic mock, NOT PDF proof.
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/android" "$tmp/tool" "$tmp/fakebin"
cp "$script_dir/c500_g0_android_renderer_lab.sh" "$tmp/tool/"
touch "$tmp/old.pdf" "$tmp/new.pdf"
cat > "$tmp/android/gradlew" <<'MOCK_GRADLE'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == *":flutter_pdf_text:connectedDebugAndroidTest"* ]] || exit 70
if [[ "${C500_TEST_NO_APK:-0}" != 1 ]]; then
  mkdir -p ../build/flutter_pdf_text/outputs/apk/androidTest/debug
  printf 'synthetic test apk' > ../build/flutter_pdf_text/outputs/apk/androidTest/debug/flutter_pdf_text-debug-androidTest.apk
fi
MOCK_GRADLE
cat > "$tmp/fakebin/adb" <<'MOCK_ADB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$C500_TEST_TRACE"
if [[ "$1" == shell && "$2" == getprop ]]; then echo 35; exit 0; fi
if [[ "$1" == install && "$2" == -r && "$3" == -t ]]; then
  [[ -f "$4" ]] || exit 71
  touch "$C500_TEST_STATE"
  echo Success
  exit 0
fi
if [[ "$1" == shell && "$2" == pm ]]; then
  if [[ -f "$C500_TEST_STATE" ]]; then
    echo 'instrumentation:me.movenext.flutter_pdf_text.test/androidx.test.runner.AndroidJUnitRunner (target=me.movenext.flutter_pdf_text.test)'
  fi
  exit 0
fi
if [[ "$1" == shell && "$2" == am ]]; then
  if [[ "${C500_TEST_PDFBOX_NEW_OOM_ABORT:-0}" == 1 && "$*" == *oldOfficialPdfiumOpenOnly* ]]; then
    printf 'STALE_PDFIUM_CRASH_MUST_NOT_LEAK\n' > "$C500_TEST_CRASH_FILE"
  fi
  if [[ "${C500_TEST_PDFBOX_NEW_OOM_ABORT:-0}" == 1 && "$*" == *newOfficialPdfBoxOpenOnly* ]]; then
    printf '%s\n' 'Fatal signal 6 (SIGABRT)' "Abort message: 'JNI NewObjectV called with pending exception java.lang.OutOfMemoryError'" > "$C500_TEST_CRASH_FILE"
    echo 'FAILURES!!!'
    exit 0
  fi
  if [[ "${C500_TEST_PDFBOX_OLD_FAIL:-0}" == 1 && "$*" == *oldOfficialPdfBoxOpenOnly* ]]; then
    echo 'FAILURES!!!'
    exit 0
  fi
  if [[ "${C500_TEST_PDFIUM_OLD_FAIL:-0}" == 1 && "$*" == *oldOfficialPdfiumOpenOnly* ]]; then
    echo 'FAILURES!!!'
    exit 0
  fi
  echo 'OK (1 test)'
  exit 0
fi
if [[ "$1" == logcat && "$2" == -b && "$3" == crash && "$4" == -c ]]; then
  : > "$C500_TEST_CRASH_FILE"
  exit 0
fi
if [[ "$1" == logcat && "$2" == -b && "$3" == crash && "$4" == -d ]]; then
  cat "$C500_TEST_CRASH_FILE"
  exit 0
fi
if [[ "$1" == logcat ]]; then exit 0; fi
if [[ "$1" == shell && "$2" == mkdir ]]; then exit 0; fi
if [[ "$1" == push ]]; then exit 0; fi
if [[ "$1" == logcat ]]; then exit 0; fi
exit 72
MOCK_ADB
chmod +x "$tmp/android/gradlew" "$tmp/fakebin/adb"
export C500_TEST_TRACE="$tmp/trace" C500_TEST_STATE="$tmp/installed" C500_TEST_CRASH_FILE="$tmp/crash-ring"
: > "$C500_TEST_CRASH_FILE"
export G0_OLD_PDF="$tmp/old.pdf" G0_NEW_PDF="$tmp/new.pdf"
(cd "$tmp/android" && PATH="$tmp/fakebin:$PATH" bash ../tool/c500_g0_android_renderer_lab.sh) > "$tmp/output" 2>&1 || {
  cat "$tmp/output" >&2
  exit 73
}
grep -Fq 'C500_G0D_INSTRUMENTATION_TEST_APK_REINSTALLED' "$tmp/output"
grep -Fq 'C500_G0D_CASE_PASS=oldOfficialPdfRendererOpenAndBoundedPages' "$tmp/output"
grep -Fq 'C500_G0D_CASE_PASS=newOfficialPdfRendererOpenAndBoundedPages' "$tmp/output"
grep -Fq 'C500_G0E_CASE_PASS=oldOfficialPdfiumOpenOnly' "$tmp/output"
grep -Fq 'C500_G0E_CASE_PASS=newOfficialPdfiumOpenOnly' "$tmp/output"
grep -Fq 'C500_G0F_CASE_PASS=oldOfficialPdfBoxOpenOnly' "$tmp/output"
grep -Fq 'C500_G0F_CASE_PASS=newOfficialPdfBoxOpenOnly' "$tmp/output"
[[ "$(grep -c '^install -r -t ' "$tmp/trace")" == 1 ]]
[[ "$(grep -c '^push ' "$tmp/trace")" == 2 ]]
[[ "$(grep -c '^shell am instrument ' "$tmp/trace")" == 6 ]]
[[ "$(grep -c '^logcat -b crash -c$' "$tmp/trace")" == 6 ]]
# A PDFium instrumentation failure must not mask the next period, and must
# produce a failing overall gate even when adb itself returns exit 0.
if (cd "$tmp/android" && C500_TEST_PDFIUM_OLD_FAIL=1 PATH="$tmp/fakebin:$PATH" bash ../tool/c500_g0_android_renderer_lab.sh) > "$tmp/pdfium-failure-output" 2>&1; then
  echo 'C500_G0E_CONTRACT_EXPECTED_PDFIUM_FAILURE' >&2
  exit 75
fi
grep -Fq 'C500_G0D_CASE_FAILED=oldOfficialPdfiumOpenOnly' "$tmp/pdfium-failure-output"
grep -Fq 'C500_G0E_CASE_PASS=newOfficialPdfiumOpenOnly' "$tmp/pdfium-failure-output"
# A failed PDFBox old-period test must not mask the new-period attempt.
if (cd "$tmp/android" && C500_TEST_PDFBOX_OLD_FAIL=1 PATH="$tmp/fakebin:$PATH" bash ../tool/c500_g0_android_renderer_lab.sh) > "$tmp/pdfbox-failure-output" 2>&1; then
  echo 'C500_G0F_CONTRACT_EXPECTED_PDFBOX_FAILURE' >&2
  exit 76
fi
grep -Fq 'C500_G0D_CASE_FAILED=oldOfficialPdfBoxOpenOnly' "$tmp/pdfbox-failure-output"
grep -Fq 'C500_G0F_CASE_PASS=newOfficialPdfBoxOpenOnly' "$tmp/pdfbox-failure-output"
# G0g: stale PDFium crash evidence must not contaminate PDFBox; secondary
# JNI abort with pending Java OOM must fail closed and be classified.
if (cd "$tmp/android" && C500_TEST_PDFBOX_NEW_OOM_ABORT=1 PATH="$tmp/fakebin:$PATH" bash ../tool/c500_g0_android_renderer_lab.sh) > "$tmp/oom-abort-output" 2>&1; then
  echo 'C500_G0G_CONTRACT_EXPECTED_OOM_ABORT_FAILURE' >&2
  exit 77
fi
grep -Fq 'C500_G0G_JAVA_HEAP_OOM_EVIDENCE=newOfficialPdfBoxOpenOnly' "$tmp/oom-abort-output"
grep -Fq 'C500_G0G_JNI_ABORT_WITH_PENDING_OOM=newOfficialPdfBoxOpenOnly' "$tmp/oom-abort-output"
grep -Fq 'C500_G0F_CASE_PASS=oldOfficialPdfBoxOpenOnly' "$tmp/oom-abort-output"
if grep -Fq 'STALE_PDFIUM_CRASH_MUST_NOT_LEAK' "$tmp/oom-abort-output"; then
  echo 'C500_G0G_STALE_NATIVE_CRASH_CONTAMINATED_PDFBOX' >&2
  exit 78
fi
rm -rf "$tmp/build" "$tmp/installed"
if (cd "$tmp/android" && C500_TEST_NO_APK=1 PATH="$tmp/fakebin:$PATH" bash ../tool/c500_g0_android_renderer_lab.sh) > "$tmp/no-apk-output" 2>&1; then
  echo 'C500_G0D_CONTRACT_EXPECTED_MISSING_APK_FAILURE' >&2
  exit 74
fi
grep -Fq 'C500_G0D_ANDROIDTEST_APK_MISSING_OR_AMBIGUOUS' "$tmp/no-apk-output"
echo 'PASS C500_G0G_MOCK_PER_CASE_CRASH_ISOLATION_JAVA_OOM_JNI_ABORT_AND_MISSING_APK_FAIL_CLOSED'
