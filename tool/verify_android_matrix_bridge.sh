#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  printf 'Usage: %s <apk> <abi> [abi ...]\n' "$0" >&2
  exit 2
fi

apk="$1"
shift
if [[ ! -f "$apk" ]]; then
  printf 'APK not found: %s\n' "$apk" >&2
  exit 1
fi

entries="$(zipinfo -1 "$apk")"
for abi in "$@"; do
  entry="lib/$abi/libkite_matrix_bridge.so"
  if ! grep -Fxq "$entry" <<<"$entries"; then
    printf 'Matrix native library missing from APK: %s\n' "$entry" >&2
    exit 1
  fi
done

printf 'Verified Matrix native library in %s for: %s\n' "$apk" "$*"
