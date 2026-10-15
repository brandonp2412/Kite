# Android builds

## Build requirements

- Common dependencies mentioned in [README.md](README.md)
- Android SDK platform 37
- Android NDK
- `cargo-ndk`
- Rust targets `aarch64-linux-android`, `armv7-linux-androideabi`, `i686-linux-android`, `x86_64-linux-android`

## Build and install on Samsung

```shell
./gradlew :androidApp:assembleRelease -PandroidAbi=arm64-v8a
adb -s 10.66.66.3:5555 install -r androidApp/build/outputs/apk/release/androidApp-release.apk
```

All build types use the single application ID `app.kite.revenge.debug`. The release variant is optimized and signed with the same local certificate as the existing Samsung installation; verify package identity and signature before installation. Do not uninstall or clear app data. Debug builds default to `arm64-v8a`, while releases without an ABI override include all supported Android ABIs.
Android Studio should detect the ABI of your target device automatically and adjust the call accordingly.

To control build ABIs manually:

```shell
./gradlew :androidApp:assembleRelease -PandroidAbi=x86_64
```
