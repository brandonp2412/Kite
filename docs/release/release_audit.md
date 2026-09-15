# Kite release audit baseline

Reviewed: 2026-09-15

This document records the executable release-security and dependency baseline. `tool/release_audit.sh` is the enforcement source; this file explains the reviewed assumptions and intentionally does not replace the final release-candidate security sign-off.

## Android and security surface

The release manifest explicitly disables Android application backup and cleartext traffic. The audit requires exactly one exported Android component, `MainActivity`, and rejects exported services, receivers, or providers. It also rejects release-debuggable, cleartext-enabled, backup-enabled, broad external-storage, and unstructured console-logging patterns in sensitive Matrix/auth/media/notification/diagnostic paths.

The current Matrix SDK boundary requires both audited encryption and encrypted persistent storage before an engine can be constructed. Per-account store configuration rejects shared encryption-key identifiers. Crash reporting serializes the exception type plus typed diagnostic context, not exception text or decrypted content. Existing Matrix deep-link parsing is typed and the production Android manifest currently exposes no `ACTION_VIEW` intent filter, so there is no OS-exported Matrix deep-link entry point in this baseline.

The final Milestone 16 security-review checkbox remains open. Access-token persistence, production SDK credential storage, encrypted media persistence/cleanup, release deep-link intent filters, and other unfinished roadmap features must be reviewed after their final implementations land.

## Clean-install verification

`tool/clean_install_test.sh` builds the Android app in Flutter release mode, removes any prior package installation, verifies the package is absent, installs the generated APK without replacement semantics, then performs both the first clean launch and a force-stopped cold relaunch while rejecting fatal Android process errors. On 2026-09-15 this passed on Nox Waydroid (`192.168.240.2:5555`) with both launches reported by Android as `LaunchState: COLD`.

This closes the clean-install test item only. The current Gradle release build still uses the debug signing configuration, so the separate reproducible signed Android release-build item remains open until the real release signing configuration and reproducibility evidence are in place.

## Dependency and license review

The reviewed `pubspec.lock` SHA-256 is:

`fe287dd286aa3c3d9acb6f2c389a0c5eeb1aca5d944345762b6594ae0f1ea289`

The lock contains only SDK or hosted packages. The executable audit rejects Git/path dependencies and requires a non-empty license or copying file for every hosted package resolved by the lock. It recognizes only the reviewed BSD-family, Apache-2.0, and MIT license texts; unknown license text fails the gate for manual review. The current baseline contains 37 hosted packages: 26 BSD-family, 9 Apache-2.0, and 2 MIT. The added `intl` 0.20.3 dependency is BSD-family and is required by Flutter's generated localisation/plural support.

Any `pubspec.lock` change deliberately fails the release audit until the changed dependency graph and licenses are reviewed and the pinned digest is updated. This makes dependency/license review an ongoing release gate instead of a one-time document.
