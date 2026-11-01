# Kite Android builds

Requirements: Android SDK 37, JDK 25, NDK, cargo-ndk, Android Rust targets and initialized Rust SDK submodule.

Build APKs using `./gradlew :androidApp:assembleDebug -PandroidAbi=arm64-v8a` or `./gradlew :androidApp:assembleRelease -PandroidAbi=arm64-v8a`.

All variants use `app.kite`. Release builds are unsigned unless the environment specifies `KITE_RELEASE_KEYSTORE`, `KITE_RELEASE_STORE_PASSWORD`, `KITE_RELEASE_KEY_ALIAS`, and `KITE_RELEASE_KEY_PASSWORD`. F-Droid can sign the unsigned result. Machine-wide Gradle init scripts can override this setting; on secondary host the local release is signed with the configured canonical signing certificate. Check `./gradlew :androidApp:signingReport` and the APK certificate before publishing binaries.

Existing private `app.kite.revenge.debug` data does not migrate automatically to `app.kite`. Preserve it; never uninstall either package to resolve a signature mismatch.

Installing `app.kite` does not transfer Matrix sessions from `app.kite.revenge.debug` or from the older Flutter Kite build. Users must sign in to the new client again, restore cross-signing/recovery keys as applicable, and only then remove older builds if they choose. Never upgrade across incompatible data formats by copying private Android app databases.

## Versioning

Kite's Android `versionCode` is calculated from `major.minor.patch` in `androidApp/build.gradle.kts`: `(major - 1) * 1_000_000 + minor * 1_000 + patch + 1`. For example, `1.0.76` becomes `77`. The major component starts at 1; minor and patch must each be below 1000. The build rejects a separate `-PandroidVersionCode` so local builds and GitHub Actions use the same calculation.

Local builds default to `1.0.76` until the source default is advanced. Pass `-PandroidVersionName=1.0.77` when building a different version; GitHub Actions passes the release tag automatically. Use `./gradlew :androidApp:printKiteAndroidVersion` to check the resolved name and code without building an APK.

**Compatibility break:** earlier test builds used 100-million-based version codes (for example `101000076`). Android will not install a lower version code over them. Do not uninstall or reset an existing `app.kite` installation to force this migration: doing so would delete its Matrix session data. The lower-code APK can only be installed on a fresh installation, or after an explicitly planned data-preserving migration.

## Tagged GitHub releases

Push a version tag (`git tag 1.0.0 && git push origin 1.0.0`) to trigger `.github/workflows/release.yml`. It builds separately for `arm64-v8a`, `armeabi-v7a`, `x86`, and `x86_64`, checks APK signatures and bundled native ABI libraries, and publishes signed APKs plus SHA-256 checksums to the matching GitHub Release. Version names match tags; Android version codes increase with semantic versions.

Configure GitHub Actions repository secrets `KITE_RELEASE_KEYSTORE_BASE64` (base64-encoded JKS), `KITE_RELEASE_STORE_PASSWORD`, `KITE_RELEASE_KEY_ALIAS`, and `KITE_RELEASE_KEY_PASSWORD` before pushing future tags. Use the same signing certificate as earlier `app.kite` builds or Android will reject updates. Never commit a keystore or passwords.
