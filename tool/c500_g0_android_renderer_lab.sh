#!/usr/bin/env bash
# C500-G0f: one-shot isolated Android API35 three-engine OPEN lab. No production app.
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
  # G0g: clear only the isolated lab emulator crash ring before each PID.
  # Prevent a previous PDFium SIGTRAP being misattributed to PDFBox.
  adb logcat -b crash -c >/dev/null
  # Isolate per-case memory stages in the dedicated lab emulator.
  adb logcat -b main -c >/dev/null
  echo "C500_G0D_CASE_BEGIN=$method"
  timeout 180s adb shell am instrument -w -r -e class "me.movenext.flutter_pdf_text.C500G0RendererLabInstrumentedTest#$method" "$runner" > "$output" 2>&1 || status=$?
  grep -E 'C500_G0D|OK \(|FAILURES|INSTRUMENTATION_' "$output" | tail -n 50 || true
  timeout 15s adb logcat -d -s C500_G0D:I C500_G0H:I AndroidRuntime:E libc:E | tail -n 60 || true
  if [[ "$status" -ne 0 ]] || ! grep -Fq 'OK (1 test)' "$output"; then
    # adb exit=0 is not a PASS: attribute the first failing instrumented case.
    # The crash ring was reset before this case; never inherit prior PID evidence.
    local crash_evidence failure_kind
    crash_evidence="$(timeout 15s adb logcat -b crash -d -t 500 || true)"
    failure_kind=INSTRUMENTATION_FAILURE
    if grep -Fq 'OutOfMemoryError' "$output" || [[ "$crash_evidence" == *'pending exception java.lang.OutOfMemoryError'* ]]; then
      failure_kind=JAVA_HEAP_OOM
    elif [[ "$crash_evidence" == *'Fatal signal 5 (SIGTRAP)'* ]]; then
      failure_kind=NATIVE_SIGTRAP
    elif grep -Fq 'java.io.IOException:' "$output"; then
      failure_kind=PDF_OPEN_IOEXCEPTION
    elif [[ "$status" -eq 124 ]]; then
      failure_kind=INSTRUMENTATION_TIMEOUT
    fi
    echo "C500_G0G_FIRST_FAILURE=$method kind=$failure_kind adb_exit=$status" >&2
    if [[ "$method" == *Pdfium* || "$method" == *PdfBox* ]]; then
      if [[ "$method" == *Pdfium* ]]; then
        echo "C500_G0E_NATIVE_CRASH_BUFFER_BEGIN=$method"
      else
        echo "C500_G0F_ENGINE_CRASH_BUFFER_BEGIN=$method"
      fi
      # G0g: this crash ring belongs to the current case after pre-case clear.
      printf '%s\n' "$crash_evidence" | grep -E 'Fatal signal|Abort message|backtrace:|#0[0-9] pc|#1[0-9] pc' | tail -n 65 || true
      if grep -Fq 'OutOfMemoryError' "$output" || [[ "$crash_evidence" == *'pending exception java.lang.OutOfMemoryError'* ]]; then
        echo "C500_G0G_JAVA_HEAP_OOM_EVIDENCE=$method"
      fi
      if [[ "$crash_evidence" == *'Fatal signal 6 (SIGABRT)'* ]] &&
         [[ "$crash_evidence" == *'pending exception java.lang.OutOfMemoryError'* ]]; then
        echo "C500_G0G_JNI_ABORT_WITH_PENDING_OOM=$method"
      fi
    fi
    echo "C500_G0D_CASE_FAILED=$method exit=$status" >&2
    return 1
  fi
  if [[ "$method" == *Pdfium* ]]; then
    echo "C500_G0E_CASE_PASS=$method (OPEN_ONLY_NOT_GLOBAL_NEGATIVE)"
  elif [[ "$method" == *PdfBox* ]]; then
    echo "C500_G0F_CASE_PASS=$method (OPEN_ONLY_NOT_GLOBAL_NEGATIVE)"
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
# Even an OOM/crash on one period cannot mask the other official file.
run_case oldOfficialPdfBoxOpenOnly || status=1
run_case newOfficialPdfBoxOpenOnly || status=1
echo "C500_G0F_THREE_ENGINE_OPEN_ONLY_NOT_GLOBAL_NEGATIVE_NOT_PRODUCTION_AUTHORITY"
exit "$status"
