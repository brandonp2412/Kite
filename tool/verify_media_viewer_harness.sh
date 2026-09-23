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

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
if [[ "${KITE_WAYDROID_LOCK_HELD:-}" != 1 || "${KITE_WAYDROID_DEVICE:-}" != "$device" ]]; then
  exec "$script_dir/with_waydroid_lock.sh" --device "$device" -- "$0" "$device"
fi

printf 'Media-viewer profile gate on %s: must PASS\n' "$device"
timeout --signal=TERM --kill-after=10s 5m \
  flutter drive \
  --profile \
  --no-dds \
  --dart-define=KITE_VIRTUALIZED_BENCHMARK=true \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/media_viewer_performance_test.dart \
  -d "$device"

printf '%s\n' 'Media-viewer profile gate passed.'
