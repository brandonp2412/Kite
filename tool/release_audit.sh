#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

fail() {
  printf 'Kite release audit failed: %s\n' "$1" >&2
  exit 1
}

main_manifest="android/app/src/main/AndroidManifest.xml"
lockfile="pubspec.lock"
reviewed_lock_sha="c7d9f3345fbc75f85b5460bda6f292870d7eee4323beffb159e1339599891589"

printf '%s\n' 'Kite release audit: Android security surface'
rg -q 'android:allowBackup="false"' "$main_manifest" || fail 'Android backups must be explicitly disabled for account/session data.'
rg -q 'android:enableOnBackInvokedCallback="true"' "$main_manifest" || fail 'Android predictive-back callback support must remain enabled.'
rg -q 'android:usesCleartextTraffic="false"' "$main_manifest" || fail 'Cleartext Android traffic must be explicitly disabled.'

exported_count="$(rg -o 'android:exported="true"' "$main_manifest" | wc -l | tr -d ' ')"
[[ "$exported_count" == "1" ]] || fail "Expected exactly one exported Android component, found $exported_count."
rg -Uq '<activity[^>]*android:name="\.MainActivity"[^>]*android:exported="true"' "$main_manifest" || \
  rg -Uq '<activity[^>]*android:exported="true"[^>]*android:name="\.MainActivity"' "$main_manifest" || \
  fail 'The only exported Android component must be MainActivity.'

if rg -Uq '<(service|receiver|provider)[^>]*android:exported="true"' "$main_manifest"; then
  fail 'Services, receivers, and providers must not be exported without an explicit reviewed exception.'
fi
if rg -q 'android:debuggable="true"|android:usesCleartextTraffic="true"|android:allowBackup="true"' "$main_manifest"; then
  fail 'Unsafe release manifest flags are present.'
fi

printf '%s\n' 'Kite release audit: secrets, diagnostics, stores, media, and SDK boundary'
sensitive_paths=(
  lib/diagnostics
  lib/features/auth
  lib/features/media
  lib/features/notifications
  lib/matrix
)
if rg -n '\b(debugPrint|debugPrintSynchronously|print)\s*\(' "${sensitive_paths[@]}"; then
  fail 'Sensitive runtime paths must not write unstructured console logs.'
fi
if rg -n 'getExternalStorageDirectory|MANAGE_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE' lib android/app/src/main; then
  fail 'Sensitive Matrix/media state must not use broad external-storage access.'
fi

rg -q 'MatrixSdkCapability\.auditedEncryption' lib/matrix/matrix_sdk_boundary.dart || fail 'Matrix SDK boundary must require audited encryption.'
rg -q 'MatrixSdkCapability\.encryptedPersistentStore' lib/matrix/matrix_sdk_boundary.dart || fail 'Matrix SDK boundary must require encrypted persistent storage.'
rg -q 'must not share encryption keys across accounts' lib/matrix/matrix_account_store_registry.dart || fail 'Account stores must enforce unique encryption keys.'
rg -q 'error\.runtimeType\.toString\(\)' lib/diagnostics/crash_reporting.dart || fail 'Crash diagnostics must record error type without serializing error text.'
if rg -q 'error\.toString\(\)' lib/diagnostics/crash_reporting.dart; then
  fail 'Crash diagnostics must not serialize exception text.'
fi

printf '%s\n' 'Kite release audit: dependency provenance and licenses'
actual_lock_sha="$(sha256sum "$lockfile" | awk '{print $1}')"
[[ "$actual_lock_sha" == "$reviewed_lock_sha" ]] || fail 'pubspec.lock changed since the dependency/license review; review dependencies and update the pinned digest.'

if rg -n 'source: (git|path)' "$lockfile"; then
  fail 'Git/path dependencies require an explicit dependency review before release.'
fi

pub_cache="${PUB_CACHE:-$HOME/.pub-cache}"
license_failures=0
hosted_count=0
bsd_count=0
mit_count=0
apache_count=0
while read -r package version; do
  [[ -n "$package" && -n "$version" ]] || continue
  hosted_count=$((hosted_count + 1))
  package_dir="$(find "$pub_cache/hosted" -maxdepth 2 -type d -name "$package-$version" -print -quit 2>/dev/null || true)"
  if [[ -z "$package_dir" ]]; then
    printf 'Missing cached package for license audit: %s %s\n' "$package" "$version" >&2
    license_failures=$((license_failures + 1))
    continue
  fi
  license_file="$(find "$package_dir" -maxdepth 1 -type f \( -iname 'LICENSE' -o -iname 'LICENSE.*' -o -iname 'COPYING' -o -iname 'COPYING.*' \) -size +0c -print -quit)"
  if [[ -z "$license_file" ]]; then
    printf 'Missing non-empty license file: %s %s\n' "$package" "$version" >&2
    license_failures=$((license_failures + 1))
    continue
  fi

  if rg -qi 'Apache License.*Version 2\.0' "$license_file"; then
    apache_count=$((apache_count + 1))
  elif rg -qi 'Permission is hereby granted, free of charge' "$license_file"; then
    mit_count=$((mit_count + 1))
  elif rg -qi 'Redistribution and use in source and binary forms' "$license_file"; then
    bsd_count=$((bsd_count + 1))
  else
    printf 'Unreviewed dependency license text: %s %s (%s)\n' "$package" "$version" "$license_file" >&2
    license_failures=$((license_failures + 1))
  fi
done < <(
  awk '
    /^  [^ ]+:$/ { package=$1; sub(":$", "", package); source=""; version="" }
    /    source:/ { source=$2 }
    /    version:/ {
      version=$2
      gsub(/"/, "", version)
      if (source == "hosted") print package, version
    }
  ' "$lockfile"
)

[[ "$hosted_count" -gt 0 ]] || fail 'No hosted dependencies were discovered in pubspec.lock.'
[[ "$license_failures" == "0" ]] || fail "$license_failures dependency license checks failed."
printf 'Kite release audit passed: %s hosted dependency licenses verified (%s BSD, %s Apache-2.0, %s MIT).\n' \
  "$hosted_count" "$bsd_count" "$apache_count" "$mit_count"
