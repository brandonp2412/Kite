#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' 'Kite quality gate: Waydroid lock self-test'
"$(dirname "$0")/verify_waydroid_lock.sh"

printf '%s\n' 'Kite quality gate: analyze'
flutter analyze

printf '%s\n' 'Kite quality gate: deterministic tests'
flutter test

printf '%s\n' 'Kite quality gate: Waydroid jitter self-test'
"$(dirname "$0")/verify_jitter_harness.sh" "${1:-}"

printf '%s\n' 'Kite quality gate passed.'
