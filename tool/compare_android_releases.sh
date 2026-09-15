#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf 'Usage: %s FIRST.apk SECOND.apk\n' "$0" >&2
  exit 2
fi

first="$1"
second="$2"
[[ -f "$first" ]] || { printf 'Missing APK: %s\n' "$first" >&2; exit 2; }
[[ -f "$second" ]] || { printf 'Missing APK: %s\n' "$second" >&2; exit 2; }

apksigner="${KITE_APKSIGNER:-$(command -v apksigner || true)}"
[[ -n "$apksigner" ]] || { printf 'apksigner was not found.\n' >&2; exit 2; }

fingerprint() {
  "$apksigner" verify --print-certs "$1" |
    sed -n 's/^V2 Signer: certificate SHA-256 digest: //p' |
    tr -d ':[:space:]' |
    tr 'A-F' 'a-f'
}

first_fingerprint="$(fingerprint "$first")"
second_fingerprint="$(fingerprint "$second")"
[[ -n "$first_fingerprint" ]] || { printf 'First APK has no verified v2 signer.\n' >&2; exit 1; }
[[ "$first_fingerprint" == "$second_fingerprint" ]] || {
  printf 'Signer mismatch.\n' >&2
  exit 1
}

first_entries="$(mktemp)"
second_entries="$(mktemp)"
trap 'rm -f "$first_entries" "$second_entries"' EXIT

zipinfo -1 "$first" >"$first_entries"
zipinfo -1 "$second" >"$second_entries"
cmp -s "$first_entries" "$second_entries" || {
  printf 'APK entry lists differ.\n' >&2
  diff -u "$first_entries" "$second_entries" || true
  exit 1
}

while IFS= read -r entry; do
  first_hash="$(unzip -p "$first" "$entry" | sha256sum | awk '{print $1}')"
  second_hash="$(unzip -p "$second" "$entry" | sha256sum | awk '{print $1}')"
  if [[ "$first_hash" != "$second_hash" ]]; then
    printf 'APK payload differs: %s\n' "$entry" >&2
    exit 1
  fi
done <"$first_entries"

if cmp -s "$first" "$second"; then
  printf 'Android release reproducibility: PASS (byte-identical, signer %s).\n' "$first_fingerprint"
  exit 0
fi

printf 'Android release reproducibility: FAIL. ZIP entry payloads and signer certificate match, but signed APK bytes differ.\n' >&2
printf 'Signer certificate SHA-256: %s\n' "$first_fingerprint" >&2
exit 1
