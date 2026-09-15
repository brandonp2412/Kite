#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
device="lock-self-test-$$"
lock_device="${device//[^[:alnum:]._-]/_}"
lock_file="/tmp/kite-waydroid-${lock_device}.lock"
trap 'rm -f "$lock_file"' EXIT

exec 8>"$lock_file"
flock -n 8

set +e
output="$("$script_dir"/with_waydroid_lock.sh --device "$device" --wait 0.05 -- true 2>&1)"
status=$?
set -e

if [[ $status -ne 3 ]]; then
  printf 'Expected lock contention to exit 3, got %d. Output: %s\n' "$status" "$output" >&2
  exit 1
fi

flock -u 8
"$script_dir/with_waydroid_lock.sh" --device "$device" --wait 0.05 -- true >/dev/null
printf '%s\n' 'Waydroid lock self-test passed.'
