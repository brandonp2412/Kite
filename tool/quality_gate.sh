#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' 'Kite quality gate: Waydroid lock self-test'
"$(dirname "$0")/verify_waydroid_lock.sh"

printf '%s\n' 'Kite quality gate: release audit'
"$(dirname "$0")/release_audit.sh"

printf '%s\n' 'Kite quality gate: Matrix Rust bridge'
cargo fmt --manifest-path rust/kite_matrix_bridge/Cargo.toml --check
cargo test --manifest-path rust/kite_matrix_bridge/Cargo.toml --locked -- --test-threads=1
cargo build --manifest-path rust/kite_matrix_bridge/Cargo.toml --locked

printf '%s\n' 'Kite quality gate: analyze'
flutter analyze

printf '%s\n' 'Kite quality gate: Dart/Rust Matrix ABI smoke test'
KITE_MATRIX_BRIDGE_LIBRARY="$PWD/rust/kite_matrix_bridge/target/debug/libkite_matrix_bridge.so" \
  flutter test test/matrix_rust_native_bridge_test.dart

printf '%s\n' 'Kite quality gate: deterministic tests'
flutter test

printf '%s\n' 'Kite quality gate: Waydroid jitter self-test'
"$(dirname "$0")/verify_jitter_harness.sh" "${1:-}"

printf '%s\n' 'Kite quality gate: back-navigation profile test'
"$(dirname "$0")/verify_back_navigation_harness.sh" "${1:-}"

printf '%s\n' 'Kite quality gate passed.'
