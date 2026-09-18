# Kite release audit baseline

Reviewed: 2026-09-17

This document records the executable release-security and dependency baseline. `tool/release_audit.sh` is the enforcement source; this file explains the reviewed assumptions and intentionally does not replace the final release-candidate security sign-off.

## Android and security surface

The release manifest explicitly disables Android application backup and cleartext traffic and opts into Android's back-invoked callback path so current Android releases do not fall back to the legacy back dispatcher. The audit requires exactly one exported Android component, `MainActivity`, and rejects exported services, receivers, or providers. It also rejects release-debuggable, cleartext-enabled, backup-enabled, broad external-storage, and unstructured console-logging patterns in sensitive Matrix/auth/media/notification/diagnostic paths.

The current Matrix SDK boundary requires both audited encryption and encrypted persistent storage before an engine can be constructed. Per-account store configuration rejects shared encryption-key identifiers. Crash reporting serializes the exception type plus typed diagnostic context, not exception text or decrypted content. Existing Matrix deep-link parsing is typed and the production Android manifest currently exposes no `ACTION_VIEW` intent filter, so there is no OS-exported Matrix deep-link entry point in this baseline.

The final Milestone 16 security-review checkbox remains open. Access-token persistence, production SDK credential storage, encrypted media persistence/cleanup, release deep-link intent filters, and other unfinished roadmap features must be reviewed after their final implementations land.

## Clean-install verification

Reverified on 2026-09-16 on Nox Waydroid (`192.168.240.2:5555`): the release APK built successfully from this branch, installation began from an empty package state, and both the first launch and force-stopped relaunch reported `LaunchState: COLD` with no fatal Android process error.

`tool/clean_install_test.sh` builds the Android app in Flutter release mode, removes any prior package installation, verifies the package is absent, installs the generated APK without replacement semantics, then performs both the first clean launch and a force-stopped cold relaunch while rejecting fatal Android process errors. On 2026-09-15 this passed on Nox Waydroid (`192.168.240.2:5555`) with both launches reported by Android as `LaunchState: COLD`.

This closes the clean-install test item only. The current Gradle release build still uses the debug signing configuration, so the separate reproducible signed Android release-build item remains open until the real release signing configuration and reproducibility evidence are in place.

## Signed-build reproducibility investigation

Two clean Android release builds were produced on Glass on 2026-09-15 with the same source tree, release key, build name (`1.0.0`) and build number (`424242`). Both APKs verify with Android APK Signature Scheme v2 and the same release certificate, but their whole-file SHA-256 digests differ. A complete entry-by-entry comparison found identical ZIP entry names and identical uncompressed payload hashes, so the remaining byte difference is outside the packaged entry payloads in signing/archive structure.

`tool/compare_android_releases.sh` now makes this distinction explicit: it verifies the v2 signer certificate, entry list, each uncompressed entry payload and finally whole-file identity. The two clean builds intentionally fail the final byte-identity check. Therefore the Milestone 16 reproducible signed Android release-build item remains open; matching payloads and signer identity are useful evidence but are not being treated as bit-for-bit reproducibility.

## Dependency and license review

Reverified on 2026-09-18: the executable audit passed with all 59 hosted packages accounted for (47 BSD-family, 10 Apache-2.0, and 2 MIT).

The reviewed `pubspec.lock` SHA-256 is:

`f32502dbb56e5609828a2f9672acddbf01316c27b542426df08cde3d295511df`

The lock contains only SDK or hosted packages. The executable audit rejects Git/path dependencies and requires a non-empty license or copying file for every hosted package resolved by the lock. It recognizes only the reviewed BSD-family, Apache-2.0, and MIT license texts; unknown license text fails the gate for manual review. The current baseline contains 59 hosted packages: 47 BSD-family, 10 Apache-2.0, and 2 MIT. The added `intl` 0.20.3 dependency is BSD-family and is required by Flutter's generated localisation/plural support. The later `ffi` 2.2.0 direct dependency is also BSD-family and is required by the Matrix Rust native bridge. The `file_selector` 1.1.0 dependency and its resolved cross-platform selector stack add 13 hosted packages for production avatar selection: 12 BSD-family and one Apache-2.0 (`file_selector_android`). The `url_launcher` 6.3.2 dependency and its resolved cross-platform launcher stack add 8 BSD-family packages for opening timeline web links through the platform browser. All resolved package license files match the executable audit's reviewed license families.

Any `pubspec.lock` change deliberately fails the release audit until the changed dependency graph and licenses are reviewed and the pinned digest is updated. This makes dependency/license review an ongoing release gate instead of a one-time document.
