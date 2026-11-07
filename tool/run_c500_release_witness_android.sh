#!/usr/bin/env bash
# CI-only Android API35 release-AOT witness; no production key or user data.
set -euo pipefail
apk="$1"
test -s "$apk"
sdk="$(printenv ANDROID_SDK_ROOT || printenv ANDROID_HOME || true)"
test -n "$sdk"
aapt="$(find "$sdk/build-tools" -maxdepth 2 -type f -name aapt | sort -V | tail -n 1)"
test -n "$aapt"
package="$("$aapt" dump badging "$apk" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -n 1)"
test -n "$package"
echo "C500_RELEASE_WITNESS_APK_PACKAGE=$package"
adb logcat -c
adb install -r "$apk"
adb shell monkey -p "$package" -c android.intent.category.LAUNCHER 1
for attempt in $(seq 1 90); do
  logs="$(adb logcat -d -s flutter:I '*:S' || true)"
  if grep -Fq 'C500_RELEASE_WITNESS_FAIL' <<< "$logs"; then
    echo "$logs" | grep -F 'C500_RELEASE_WITNESS_' || true
    exit 65
  fi
  if grep -Fq 'C500_RELEASE_WITNESS_PASS' <<< "$logs"; then
    if ! grep -Fq 'C500_RELEASE_V24_LEDGER_PASS' <<< "$logs"; then
      echo 'C500_RELEASE_V24_LEDGER_MARKER_MISSING' >&2
      exit 67
    fi
    if ! grep -Fq 'C500_RELEASE_MAIN_ROUTER_PASS' <<< "$logs"; then
      echo 'C500_RELEASE_MAIN_ROUTER_MARKER_MISSING' >&2
      exit 68
    fi
    if ! grep -Fq 'C500_RELEASE_MAIN_CONSENT_NO_WRITE_PASS' <<< "$logs"; then
      echo 'C500_RELEASE_MAIN_CONSENT_NO_WRITE_MARKER_MISSING' >&2
      exit 69
    fi
    echo "$logs" | grep -E 'C500_RELEASE_(MAIN_ROUTER|MAIN_CONSENT_NO_WRITE|V24_LEDGER|WITNESS)_PASS'
    exit 0
  fi
  sleep 2
done
echo 'C500_RELEASE_WITNESS_TIMEOUT_NO_TERMINAL_MARKER' >&2
adb logcat -d -s flutter:I '*:S' | tail -n 80 >&2 || true
exit 66
