# Kite Android builds

Requirements: Android SDK 37, JDK 25, NDK, cargo-ndk, Android Rust targets and initialized Rust SDK submodule.

Build APKs using `./gradlew :androidApp:assembleDebug -PandroidAbi=arm64-v8a` or `./gradlew :androidApp:assembleRelease -PandroidAbi=arm64-v8a`.

All variants use `app.kite`. Release builds are unsigned unless the environment specifies `KITE_RELEASE_KEYSTORE`, `KITE_RELEASE_STORE_PASSWORD`, `KITE_RELEASE_KEY_ALIAS`, and `KITE_RELEASE_KEY_PASSWORD`. F-Droid can sign the unsigned result. Machine-wide Gradle init scripts can override this setting; on secondary host the local release is signed with the configured canonical signing certificate. Check `./gradlew :androidApp:signingReport` and the APK certificate before publishing binaries.

Existing private `app.kite.revenge.debug` data does not migrate automatically to `app.kite`. Preserve it; never uninstall either package to resolve a signature mismatch.

Installing `app.kite` does not transfer Matrix sessions from `app.kite.revenge.debug` or from the older Flutter Kite build. Users must sign in to the new client again, restore cross-signing/recovery keys as applicable, and only then remove older builds if they choose. Never upgrade across incompatible data formats by copying private Android app databases.

## Versioning

Kite Android `versionCode` is derived from `major.minor.patch` as `101_000_000 + (major - 1) * 1_000_000 + minor * 1_000 + patch + 1`. Thus `1.0.77` becomes `101000078`. This compatibility floor preserves in-place upgrades over already installed production builds; minor and patch must stay below 1000.

Local builds default to `1.0.77`. Override with `-PandroidVersionName=1.0.78` when needed. GitHub Actions passes the release tag. Use `./gradlew :androidApp:printKiteAndroidVersion` to confirm the code before building.

**Compatibility:** Previous production `app.kite` builds have version codes such as `101000076`. The attempted lower version-code scheme would have prevented in-place updates and was never installed. The compatibility floor is restored. Never uninstall/reset Kite to resolve a version-code mismatch: that deletes Matrix accounts.

## Tagged GitHub releases

Push a version tag (`git tag 1.0.0 && git push origin 1.0.0`) to trigger `.github/workflows/release.yml`. It builds separately for `arm64-v8a`, `armeabi-v7a`, `x86`, and `x86_64`, checks APK signatures and bundled native ABI libraries, and publishes signed APKs plus SHA-256 checksums to the matching GitHub Release. Version names match tags; Android version codes increase with semantic versions.

Configure GitHub Actions repository secrets `KITE_RELEASE_KEYSTORE_BASE64` (base64-encoded JKS), `KITE_RELEASE_STORE_PASSWORD`, `KITE_RELEASE_KEY_ALIAS`, and `KITE_RELEASE_KEY_PASSWORD` before pushing future tags. Use the same signing certificate as earlier `app.kite` builds or Android will reject updates. Never commit a keystore or passwords.
