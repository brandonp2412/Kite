# Kite release audit baseline

Reviewed: 2026-09-15

This document records the executable release-security and dependency baseline. `tool/release_audit.sh` is the enforcement source; this file explains the reviewed assumptions and intentionally does not replace the final release-candidate security sign-off.

## Android and security surface

The release manifest explicitly disables Android application backup and cleartext traffic. The audit requires exactly one exported Android component, `MainActivity`, and rejects exported services, receivers, or providers. It also rejects release-debuggable, cleartext-enabled, backup-enabled, broad external-storage, and unstructured console-logging patterns in sensitive Matrix/auth/media/notification/diagnostic paths.

The current Matrix SDK boundary requires both audited encryption and encrypted persistent storage before an engine can be constructed. Per-account store configuration rejects shared encryption-key identifiers. Crash reporting serializes the exception type plus typed diagnostic context, not exception text or decrypted content. Existing Matrix deep-link parsing is typed and the production Android manifest currently exposes no `ACTION_VIEW` intent filter, so there is no OS-exported Matrix deep-link entry point in this baseline.

The final Milestone 16 security-review checkbox remains open. Access-token persistence, production SDK credential storage, encrypted media persistence/cleanup, release deep-link intent filters, and other unfinished roadmap features must be reviewed after their final implementations land.

## Dependency and license review

The reviewed `pubspec.lock` SHA-256 is:

`cdd8459a752084813f8dbc9b3a33cb3d66d58286b3fe50e21c11eddfe3f978fd`

The lock contains only SDK or hosted packages. The executable audit rejects Git/path dependencies and requires a non-empty license or copying file for every hosted package resolved by the lock. It recognizes only the reviewed BSD-family, Apache-2.0, and MIT license texts; unknown license text fails the gate for manual review. The current baseline contains 36 hosted packages: 25 BSD-family, 9 Apache-2.0, and 2 MIT.

Any `pubspec.lock` change deliberately fails the release audit until the changed dependency graph and licenses are reviewed and the pinned digest is updated. This makes dependency/license review an ongoing release gate instead of a one-time document.
