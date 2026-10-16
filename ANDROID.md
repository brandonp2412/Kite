# Kite Android builds

Requirements: Android SDK 37, JDK 25, NDK, cargo-ndk, Android Rust targets and initialized Rust SDK submodule.

Build APKs using `./gradlew :androidApp:assembleDebug -PandroidAbi=arm64-v8a` or `./gradlew :androidApp:assembleRelease -PandroidAbi=arm64-v8a`.

All variants use `app.kite`. Release builds are unsigned unless the environment specifies `KITE_RELEASE_KEYSTORE`, `KITE_RELEASE_STORE_PASSWORD`, `KITE_RELEASE_KEY_ALIAS`, and `KITE_RELEASE_KEY_PASSWORD`. F-Droid can sign the unsigned result.

Existing private `app.kite.revenge.debug` data does not migrate automatically to `app.kite`. Preserve it; never uninstall either package to resolve a signature mismatch.
