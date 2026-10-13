# Kite Native (SchildiChat Revenge) migration

## Goal and constraints

The user reports that SchildiChat Revenge has essentially zero perceptible UI lag on Samsung Galaxy S25, but finds its interface ugly/confusing. Use Revenge's native Kotlin/Jetpack Compose + Matrix Rust SDK architecture as the foundation for Kite. Reproduce **Kite's existing icon, visual style, and custom chat/reaction features**, and simplify navigation without slowing frame rendering. The original Flutter Kite app at `/home/brandon/kite` is the source of truth for feature details and must remain installed/unaltered until the replacement is ready.

- This repo: `/home/brandon/kite-revenge` on **Glass**; upstream `https://github.com/SchildiChat/schildi-revenge` at original clone `cdc162f` (GPL-3.0). Preserve upstream attribution and COPYING/LICENSE terms.
- Existing Flutter Kite: `/home/brandon/kite`, app ID `app.kite`, source version `6bdb9823f`. **Read only**; do not edit, reset or uninstall.
- New native Kite app ID: `app.kite.revenge` (debug variant `app.kite.revenge.debug`). **Never install an APK under `app.kite` until intentional, safe migration**. Preserve production Matrix app data.
- Recurring Prompta job `kite-revenge-native` is configured on Nox every **45 minutes**, starting 2026-10-14 12:06 NZDT. Prompta launches fresh ChatGPT sessions. Work on Glass and update this file every session.
- Performance acceptance: improve upon user's initial perception of Revenge without a regression in scroll smoothness, opening rooms, gesture input, search, chat-list navigation, message sending, or sync. Capture reproducible latency/JankStats frame-time data on debug/perf builds where possible, especially on the Samsung S25 at 120 Hz (8.33 ms frame budget). Avoid heavy per-row allocations or broad per-event recomposition.

## Changes so far — first implementation session, 2026-10-14

1. Cloned native Revenge into its own checkout, not into existing Kite Flutter checkout.
2. Android brand: copied exact original Kite adaptive launcher vector, matching original blue background `#003197`, changed Android title to **Kite** and its app ID to `app.kite.revenge`.
3. Copied existing Kite SVG icon artwork to graphics sources and regenerated desktop + Android-density PNG resources. Regeneration script points to the new artwork.
4. Began porting colour/shape theme: Kite purple (`#5625BA`), softer dark primary, Kite onboarding blue/purple, and rounded 18dp bubbles/containers; kept compositional structure native.
5. Added **Quick reactions** submenu to message action context menu (❤️ 👍 😂 😮 😢) using the existing `Action.Event.ToggleReactionKey` implementation. This is a first native port, **not** parity with Kite's visual popup or double-tap gesture yet.
6. No device install or E2E proof yet; any successful structural checks are **not** equivalent to an Android build or speed benchmark.

## Feature parity inventory (Flutter reference)

Use `git show 4c517c66b` in old Kite, and inspect `lib/pages/chat/events/message.dart`, `message_reactions.dart`, `chat_event_list.dart`, `chat_input_row.dart`, `chat_view.dart`, `chat_list_view.dart`, `chat_list_search_bar.dart`, `chat_app_bar_title.dart`, and `lib/widgets/chat_settings_popup_menu.dart`. Tests: `test/message_reaction_gesture_test.dart`, `test/message_more_menu_test.dart`, `test/reaction_glyph_test.dart`. The port must preserve behavior, not copy Dart UI code:

- [ ] **Fast double-tap to configured reaction**, without delaying the first single tap; tap/long-press and swipe-to-reply remain independent. Preserve no-gesture-stealing behavior when scrolling.
- [x] Initial native quick reaction action menu (❤️ 👍 😂 😮 😢), not yet equivalent to the rich popup.
- [ ] Native horizontal quick-reaction strip, visual glyphs (rounded Material heart / yellow thumbs up / custom painted laughing, surprised, sad faces; emoji fallback), optional burst, active/reverse reaction state and full emoji/sticker reaction picker. Preserve Matrix reaction equality and permissions.
- [ ] Selection-mode behavior: single tap selects only when selection is active, otherwise instant ripple; long press opens action surface with More, Select, Copy, Edit, Reply, reactions, etc. `test/message_more_menu_test.dart` validates details.
- [ ] Swipe-to-reply and responsive message interactions, composer/input toolbar & attachment picker parity.
- [ ] Chat-list, search, room headers, message bubbles, spacing, settings, account switching, dark mode and edge-to-edge layout matching Kite without Revenge's default power-user complexity.
- [ ] Notification quick reply, notification actions/copy code, unread state, search, room hide action, media, links, attachments, encryption, threading, profiles, account switching parity.
- [ ] Dedicated debug/perf build with independent app state, on-device install and logged functional/performance evidence.
- [ ] Compare Revenge original vs native Kite on same Samsung and representative large Matrix conversations; find regressions and correct them before considering replacing Flutter Kite.

## Build prerequisites / handoff

- Glass has SDK `android-37.0`, multiple Android NDK versions, `rustup` Android targets including arm64 and `java-27-openjdk` alongside default JDK17. JDK 25 is recommended by Revenge; JDK27 compatibility **not yet verified**.
- Rust SDK git submodule `matrix-rust-sdk` was **not initialized in the initial shallow clone**. `cargo-ndk` was not on PATH when checked. `./gradlew :androidApp:assembleDebug` cannot be considered tested until SDK submodule and toolchain are ready.
- On-device Android development must never replace `app.kite`. Original app remains under its prior signing key; installing build with different key under original ID would damage continuity. For any ADB operations, identify devices and package before using one. Do not uninstall production app. Keep Android debug/perf app separate.
- Workflow each run: inspect status; read this ledger; implement a coherent bounded feature slice; test; record exact evidence; commit validated progress; arrange a persistent remote/private repository when appropriate; do not claim parity prematurely.
