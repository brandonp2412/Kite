#!/usr/bin/env bash
set -euo pipefail

device="${1:-}"
if [[ -z "$device" ]]; then
  device="$(adb devices -l | awk '/model:WayDroid/{print $1; exit}')"
fi

if [[ -z "$device" ]]; then
  printf '%s\n' 'No Waydroid ADB device found. Pass a device id as the first argument.' >&2
  exit 2
fi

common=(
  timeout --signal=TERM --kill-after=10s 5m
  flutter drive
  --profile
  --no-dds
  --dart-define=KITE_VIRTUALIZED_BENCHMARK=true
  --driver=test_driver/integration_test.dart
  --target=integration_test/open_dm_performance_test.dart
  -d "$device"
)

printf '1/3 baseline on %s: must PASS\n' "$device"
"${common[@]}"

printf '2/3 injected 40ms chat-build stall: must FAIL\n'
if "${common[@]}" --dart-define=KITE_ARTIFICIAL_JITTER=true; then
  printf '%s\n' 'ERROR: jitter injector did not trip the benchmark.' >&2
  exit 1
fi

printf '3/3 clean rerun: must PASS\n'
"${common[@]}"

printf '%s\n' 'Jitter harness verified: PASS -> expected FAIL -> PASS.'
