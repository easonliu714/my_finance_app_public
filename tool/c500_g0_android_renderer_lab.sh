#!/usr/bin/env bash
# C500-G0d: one-shot isolated Android API35 PdfRenderer lab. No production app.
set -euo pipefail
: "${G0_OLD_PDF:?G0D_PINNED_OLD_SOURCE_REQUIRED}"
: "${G0_NEW_PDF:?G0D_PINNED_NEW_SOURCE_REQUIRED}"
test -f "$G0_OLD_PDF" && test -f "$G0_NEW_PDF"
adb shell getprop ro.build.version.sdk | tr -d '\r' | grep -qx '35'
./gradlew :flutter_pdf_text:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=me.movenext.flutter_pdf_text.C500G0RendererLabInstrumentedTest#provisionAndRejectWrongSourceBeforeEngineOpen --no-daemon --stacktrace
# AGP connectedAndroidTest may uninstall the test APK on completion. Restore
# exactly the APK built by this Gradle invocation before discovering the runner.
apk_root="../build/flutter_pdf_text/outputs/apk/androidTest"
if [[ ! -d "$apk_root" ]]; then
  echo "C500_G0D_ANDROIDTEST_APK_MISSING_OR_AMBIGUOUS" >&2
  exit 64
fi
mapfile -t test_apks < <(find "$apk_root" -type f -name '*.apk' -print | sort)
if [[ "${#test_apks[@]}" -ne 1 ]]; then
  echo "C500_G0D_ANDROIDTEST_APK_MISSING_OR_AMBIGUOUS count=${#test_apks[@]}" >&2
  exit 64
fi
adb install -r -t "${test_apks[0]}" >/dev/null
echo "C500_G0D_INSTRUMENTATION_TEST_APK_REINSTALLED"
instrumentations="$(adb shell pm list instrumentation | tr -d '\r')"
runner="$(printf '%s\n' "$instrumentations" | awk '/flutter_pdf_text/ {sub(/^instrumentation:/, ""); sub(/ .*/, ""); print; exit}')"
target="$(printf '%s\n' "$instrumentations" | sed -n '/flutter_pdf_text/s/.*target=\([^)]*\).*/\1/p' | head -n 1)"
if [[ -z "$runner" || -z "$target" ]]; then
  echo "C500_G0D_INSTRUMENTATION_IDENTITY_UNAVAILABLE_AFTER_REINSTALL" >&2
  exit 64
fi
echo "C500_G0D_TEST_TARGET=$target"
private_external="/sdcard/Android/data/$target/files/c500_g0_lab"
adb shell mkdir -p "$private_external"
adb push "$G0_OLD_PDF" "$private_external/old.pdf"
adb push "$G0_NEW_PDF" "$private_external/new.pdf"
echo "C500_G0D_BOTH_PINNED_FILES_PUSHED_TO_LAB_APP_EXTERNAL_DIR"
run_case() {
  local method="$1" output="c500-g0d-$1.log" status=0
  echo "C500_G0D_CASE_BEGIN=$method"
  timeout 180s adb shell am instrument -w -r -e class "me.movenext.flutter_pdf_text.C500G0RendererLabInstrumentedTest#$method" "$runner" > "$output" 2>&1 || status=$?
  grep -E 'C500_G0D|OK \(|FAILURES|INSTRUMENTATION_' "$output" | tail -n 50 || true
  timeout 15s adb logcat -d -s C500_G0D:I AndroidRuntime:E libc:E | tail -n 60 || true
  if [[ "$status" -ne 0 ]] || ! grep -Fq 'OK (1 test)' "$output"; then
    if [[ "$method" == *Pdfium* ]]; then
      echo "C500_G0E_NATIVE_CRASH_BUFFER_BEGIN=$method"
      timeout 15s adb logcat -b crash -d -t 80 | tail -n 70 || true
    fi
    echo "C500_G0D_CASE_FAILED=$method exit=$status" >&2
    return 1
  fi
  if [[ "$method" == *Pdfium* ]]; then
    echo "C500_G0E_CASE_PASS=$method (OPEN_ONLY_NOT_GLOBAL_NEGATIVE)"
  else
    echo "C500_G0D_CASE_PASS=$method (OPEN_AND_THREE_PAGES_ONLY)"
  fi
}
status=0
run_case oldOfficialPdfRendererOpenAndBoundedPages || status=1
run_case newOfficialPdfRendererOpenAndBoundedPages || status=1
# C500-G0e: two independent instrumentation processes, OPEN ONLY.
run_case oldOfficialPdfiumOpenOnly || status=1
run_case newOfficialPdfiumOpenOnly || status=1
echo "C500_G0E_PDFBOX_NOT_RUN_PDFIUM_OPEN_ONLY_NOT_GLOBAL_NEGATIVE_NOT_PRODUCTION_AUTHORITY"
exit "$status"
