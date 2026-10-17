# Kite

Kite is a fast, native [Matrix](https://matrix.org/) messenger for Android and desktop, built with Kotlin/Compose and the Matrix Rust SDK.

Kite is a fork of [SchildiChat Revenge](https://github.com/SchildiChat/schildi-revenge). We retain upstream authorship and source licensing; the Kite-specific design and development live in this repository.

## Screenshots

| Inbox | Conversation |
| --- | --- |
| ![Kite inbox with example conversations](fastlane/metadata/android/en-US/images/phoneScreenshots/1_en-US.png) | ![Kite conversation with example messages](fastlane/metadata/android/en-US/images/phoneScreenshots/2_en-US.png) |

Screenshots are illustrative, generated from anonymized sample content with `python3 scripts/generate_screenshots.py`; they are not live device captures.

## Features

- Encrypted Matrix messaging, reactions, media and formatted messages
- Multiple accounts and a unified inbox
- Native Android and desktop clients
- Keyboard navigation and customizable shortcuts
- Local message previews and search

Kite is under active development; not every Matrix feature is supported yet.

## Downloads

[GitHub releases](https://github.com/brandonp2412/Kite/releases) contain signed, architecture-specific Android APKs. Select the APK for your device (most current phones use `arm64-v8a`).

## Build

See [Android build instructions](ANDROID.md) and [upstream documentation](https://github.com/SchildiChat/schildi-revenge) for the native Rust SDK toolchain. Clone recursively to include the Matrix Rust SDK submodule.

The public Android application ID is `app.kite`. The older local-only `app.kite.revenge.debug` installation has separate data; changing application IDs does **not** migrate account sessions. Never uninstall either installation to upgrade the other.

## Privacy and licensing

See [privacy](PRIVACY.md), [license](LICENSE), and the copyright/SPDX headers in individual source files. Kite retains third-party notices, dependencies, and upstream attribution. Report bugs through [Kite issues](https://github.com/brandonp2412/Kite/issues).
