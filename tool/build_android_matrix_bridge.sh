#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

min_sdk="${KITE_ANDROID_MIN_SDK:-24}"
ndk_root="${KITE_ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME:-}}"
if [[ -z "$ndk_root" && -n "${ANDROID_HOME:-}" && -d "$ANDROID_HOME/ndk" ]]; then
  ndk_root="$(find "$ANDROID_HOME/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
fi
if [[ -z "$ndk_root" && -d /opt/android-sdk/ndk ]]; then
  ndk_root="$(find /opt/android-sdk/ndk -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
fi
if [[ -z "$ndk_root" || ! -d "$ndk_root" ]]; then
  printf 'Android NDK was not found. Set KITE_ANDROID_NDK_ROOT or ANDROID_NDK_HOME.\n' >&2
  exit 1
fi

host_tag="linux-x86_64"
toolchain="$ndk_root/toolchains/llvm/prebuilt/$host_tag/bin"
if [[ ! -d "$toolchain" ]]; then
  printf 'Android NDK LLVM toolchain was not found at %s.\n' "$toolchain" >&2
  exit 1
fi

jni_root="$repo_root/build/kite_matrix_bridge/jniLibs"
rm -rf "$jni_root"
mkdir -p "$jni_root"

requested_abis=("$@")
if [[ ${#requested_abis[@]} -eq 0 ]]; then
  requested_abis=(arm64-v8a armeabi-v7a x86_64)
fi

abi_requested() {
  local candidate="$1"
  local requested
  for requested in "${requested_abis[@]}"; do
    if [[ "$requested" == "$candidate" ]]; then
      return 0
    fi
  done
  return 1
}

build_target() {
  local rust_target="$1"
  local abi="$2"
  local clang_prefix="$3"
  local env_suffix="${rust_target//-/_}"
  local clang="$toolchain/${clang_prefix}${min_sdk}-clang"
  local clangxx="$toolchain/${clang_prefix}${min_sdk}-clang++"
  local linker_var="CARGO_TARGET_${env_suffix^^}_LINKER"
  local cc_var="CC_${env_suffix}"
  local cxx_var="CXX_${env_suffix}"
  local ar_var="AR_${env_suffix}"

  if [[ ! -x "$clang" || ! -x "$clangxx" ]]; then
    printf 'Android compiler for %s was not found under %s.\n' "$rust_target" "$toolchain" >&2
    exit 1
  fi

  env \
    "$cc_var=$clang" \
    "$cxx_var=$clangxx" \
    "$ar_var=$toolchain/llvm-ar" \
    "$linker_var=$clang" \
    cargo build \
      --manifest-path rust/kite_matrix_bridge/Cargo.toml \
      --locked \
      --release \
      --target "$rust_target"

  mkdir -p "$jni_root/$abi"
  cp "rust/kite_matrix_bridge/target/$rust_target/release/libkite_matrix_bridge.so" \
    "$jni_root/$abi/libkite_matrix_bridge.so"
}

if abi_requested arm64-v8a; then
  build_target aarch64-linux-android arm64-v8a aarch64-linux-android
fi
if abi_requested armeabi-v7a; then
  build_target armv7-linux-androideabi armeabi-v7a armv7a-linux-androideabi
fi
if abi_requested x86_64; then
  build_target x86_64-linux-android x86_64 x86_64-linux-android
fi

printf 'Built Matrix Android JNI libraries under %s for: %s.\n' "$jni_root" "${requested_abis[*]}"
