#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

properties_file="${KITE_ANDROID_KEY_PROPERTIES:-$HOME/.config/android-signing/fdroid.properties}"
github_repo="${KITE_GITHUB_REPO:-brandonp2412/Kite}"
flexify_repo="${KITE_FLEXIFY_REPO:-brandonp2412/Flexify}"
build_number="${KITE_BUILD_NUMBER:-$(date +%s)}"

if [[ ! -f "$properties_file" ]]; then
  printf 'Android signing properties are missing.\n' >&2
  exit 1
fi

store_file="$(sed -n 's/^storeFile=//p' "$properties_file")"
if [[ -z "$store_file" ]]; then
  printf 'Android signing properties do not define storeFile.\n' >&2
  exit 1
fi
if [[ "$store_file" != /* ]]; then
  store_file="$repo_root/android/app/$store_file"
fi
if [[ ! -f "$store_file" ]]; then
  printf 'Android signing keystore is missing.\n' >&2
  exit 1
fi

ln -sfn "$properties_file" android/key.properties

flutter pub get
flutter analyze
mapfile -t tests < <(find test -type f -name '*_test.dart' ! -name 'golden_*' | sort)
flutter test "${tests[@]}"

flutter build apk --release --build-number "$build_number"
mv build/app/outputs/flutter-apk/app-release.apk build/app/outputs/flutter-apk/kite.apk
flutter build apk --release --split-per-abi --target-platform android-arm64 --build-number "$build_number"

if [[ -z "${GH_TOKEN:-}" && -f "$HOME/.config/shell/private.env" ]]; then
  set -a
  source "$HOME/.config/shell/private.env"
  set +a
fi
if [[ -z "${GH_TOKEN:-}" ]]; then
  printf 'GH_TOKEN is required to publish the GitHub release.\n' >&2
  exit 1
fi

export TERM=dumb NO_COLOR=1 GH_PAGER=cat GH_PROMPT_DISABLED=1

apksigner="$(find /opt/android-sdk/build-tools "${ANDROID_HOME:-/nonexistent}/build-tools" -type f -name apksigner 2>/dev/null | sort -V | tail -1)"
if [[ -z "$apksigner" ]]; then
  printf 'apksigner was not found.\n' >&2
  exit 1
fi

kite_fingerprint="$($apksigner verify --print-certs build/app/outputs/flutter-apk/kite.apk | sed -n 's/^V2 Signer: certificate SHA-256 digest: //p' | tr -d ':[:space:]' | tr 'A-F' 'a-f')"
reference_dir="$(mktemp -d)"
trap 'rm -rf "$reference_dir"' EXIT
gh release download --repo "$flexify_repo" --pattern flexify.apk --dir "$reference_dir"
flexify_fingerprint="$($apksigner verify --print-certs "$reference_dir/flexify.apk" | sed -n 's/^V2 Signer: certificate SHA-256 digest: //p' | tr -d ':[:space:]' | tr 'A-F' 'a-f')"
if [[ -z "$kite_fingerprint" || "$kite_fingerprint" != "$flexify_fingerprint" ]]; then
  printf 'Kite APK signing certificate does not match the latest Flexify release.\n' >&2
  exit 1
fi

sha="$(git rev-parse HEAD)"
gh release delete android-latest --repo "$github_repo" --cleanup-tag --yes >/dev/null 2>&1 || true
gh release create android-latest \
  build/app/outputs/flutter-apk/kite.apk \
  build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  --repo "$github_repo" \
  --target "$sha" \
  --title 'Kite Android (latest)' \
  --notes "Signed Android build from ${sha:0:7}. Build number ${build_number}." \
  --latest

printf 'Published signed Kite APK for %s (build %s).\n' "${sha:0:7}" "$build_number"
