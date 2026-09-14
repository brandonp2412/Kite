#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

device="${1:-}"
if [[ -z "$device" ]]; then
  device="$(adb devices -l | awk '/model:WayDroid/{print $1; exit}')"
fi

if [[ -z "$device" ]]; then
  printf '%s\n' 'No Waydroid ADB device found. Pass a device id as the first argument.' >&2
  exit 2
fi

package_name="nz.presley.kite"
activity_name="$package_name/.MainActivity"
apk="build/app/outputs/flutter-apk/app-release.apk"

printf 'Clean-install test on %s: build release APK\n' "$device"
timeout --signal=TERM --kill-after=15s 5m flutter build apk --release
[[ -s "$apk" ]] || {
  printf 'Release APK missing: %s\n' "$apk" >&2
  exit 1
}

printf '%s\n' 'Remove any existing installation and verify package state is empty.'
adb -s "$device" uninstall "$package_name" >/dev/null 2>&1 || true
if [[ -n "$(adb -s "$device" shell pm path "$package_name" 2>/dev/null | tr -d '\r')" ]]; then
  printf '%s\n' 'Package still exists after uninstall.' >&2
  exit 1
fi

printf '%s\n' 'Install release APK into a clean package state.'
adb -s "$device" install "$apk" >/dev/null
[[ -n "$(adb -s "$device" shell pm path "$package_name" | tr -d '\r')" ]] || {
  printf '%s\n' 'Package is not installed after adb install.' >&2
  exit 1
}

launch_and_verify() {
  local label="$1"
  adb -s "$device" logcat -c
  adb -s "$device" shell am force-stop "$package_name"
  local launch_output
  launch_output="$(adb -s "$device" shell am start -W -n "$activity_name")"
  printf '%s\n' "$launch_output"
  sleep 2
  local pid
  pid="$(adb -s "$device" shell pidof "$package_name" | tr -d '\r')"
  if [[ -z "$pid" ]]; then
    printf '%s launch exited before verification.\n' "$label" >&2
    adb -s "$device" logcat -d -t 200 >&2 || true
    exit 1
  fi
  if adb -s "$device" logcat -d -t 300 | rg -q 'FATAL EXCEPTION|Process: nz\.presley\.kite.*has died|Fatal signal'; then
    printf '%s launch emitted a fatal Android process error.\n' "$label" >&2
    adb -s "$device" logcat -d -t 300 >&2 || true
    exit 1
  fi
  printf '%s launch PASS (pid %s).\n' "$label" "$pid"
}

launch_and_verify 'First clean'
launch_and_verify 'Cold relaunch'

printf '%s\n' 'Clean-install release-mode test passed.'
