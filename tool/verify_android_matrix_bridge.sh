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

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
mapfile -t required_symbols < <(
  rg -o 'kite_matrix_[A-Za-z0-9_]+' \
    "$repo_root/lib/matrix/matrix_rust_native_bridge.dart" |
    sort -u
)

entries="$(zipinfo -1 "$apk")"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

for abi in "$@"; do
  entry="lib/$abi/libkite_matrix_bridge.so"
  if ! grep -Fxq "$entry" <<<"$entries"; then
    printf 'Matrix native library missing from APK: %s\n' "$entry" >&2
    exit 1
  fi

  library="$tmp_dir/libkite_matrix_bridge-$abi.so"
  unzip -p "$apk" "$entry" >"$library"
  exports="$(nm -D --defined-only "$library")"
  for symbol in "${required_symbols[@]}"; do
    if ! grep -Eq "[[:space:]]${symbol}$" <<<"$exports"; then
      printf 'Matrix native symbol missing from %s: %s\n' "$entry" "$symbol" >&2
      exit 1
    fi
  done
done

printf 'Verified Matrix native library ABI and exported symbols in %s for: %s\n' "$apk" "$*"
