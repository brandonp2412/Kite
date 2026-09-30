#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:-}"
APK="build/app/outputs/flutter-apk/app-release.apk"
PACKAGE="app.kite"

if [[ -z "$DEVICE" ]]; then
  mapfile -t DEVICES < <(adb devices | awk 'NR > 1 && $2 == "device" {print $1}')
  if [[ ${#DEVICES[@]} -ne 1 ]]; then
    echo "Expected exactly one connected Android device; found ${#DEVICES[@]}." >&2
    echo "Pass the device serial explicitly: $0 <adb-serial>" >&2
    exit 2
  fi
  DEVICE="${DEVICES[0]}"
fi

if ! adb -s "$DEVICE" get-state >/dev/null 2>&1; then
  echo "Android device '$DEVICE' is not connected." >&2
  exit 2
fi

echo "Building Kite release APK..."
flutter build apk --release

if [[ ! -f "$APK" ]]; then
  echo "Release APK not found at $APK" >&2
  exit 1
fi

if adb -s "$DEVICE" shell pm path "$PACKAGE" >/dev/null 2>&1; then
  echo "Updating existing $PACKAGE in place (app data will be preserved)..."
else
  echo "Installing $PACKAGE..."
fi

set +e
INSTALL_OUTPUT="$(adb -s "$DEVICE" install -t -r "$APK" 2>&1)"
INSTALL_STATUS=$?
set -e
printf '%s\n' "$INSTALL_OUTPUT"

if [[ $INSTALL_STATUS -ne 0 ]] || grep -q '^Failure' <<<"$INSTALL_OUTPUT"; then
  cat >&2 <<'EOF'

Install failed safely. The existing Kite installation was NOT uninstalled.

Common causes:
  - INSTALL_FAILED_UPDATE_INCOMPATIBLE: signing key mismatch
  - INSTALL_FAILED_VERSION_DOWNGRADE: APK versionCode is lower than installed version

Do not work around these failures by uninstalling the existing app unless data loss is explicitly intended.
EOF
  exit 1
fi

echo "Kite installed without uninstalling the existing package."
