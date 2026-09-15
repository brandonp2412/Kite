#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' 'Usage: tool/with_waydroid_lock.sh [--device DEVICE] [--wait SECONDS] -- COMMAND [ARGS...]' >&2
}

device=''
wait_seconds="${KITE_WAYDROID_LOCK_WAIT_SECONDS:-60}"

while (($#)); do
  case "$1" in
    --device)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      device="$2"
      shift 2
      ;;
    --wait)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      wait_seconds="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if (($# == 0)); then
  usage
  exit 2
fi

if [[ -z "$device" ]]; then
  device="$(adb devices -l | awk '/model:WayDroid/{print $1; exit}')"
fi

if [[ -z "$device" ]]; then
  printf '%s\n' 'No Waydroid ADB device found. Pass --device DEVICE.' >&2
  exit 2
fi

lock_device="${device//[^[:alnum:]._-]/_}"
lock_file="/tmp/kite-waydroid-${lock_device}.lock"
exec 9>"$lock_file"
if ! flock -w "$wait_seconds" 9; then
  printf 'Timed out waiting for exclusive Waydroid access: %s\n' "$device" >&2
  exit 3
fi

export KITE_WAYDROID_DEVICE="$device"
export KITE_WAYDROID_LOCK_HELD=1
printf 'Acquired exclusive Waydroid access: %s\n' "$device"
exec "$@"
