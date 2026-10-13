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

## Changes so far — second implementation session, 2026-10-14

1. Re-read the original Kite gesture/action tests and MessageReactionSurface implementation. Confirmed the key behavior: the first tap remains immediate, a nearby second short tap triggers the configured reaction, and drag/long-press/multi-touch cancel the double-tap candidate.
2. Added native **Double-tap to react** and **Double-tap reaction** preferences under Conversation → Message actions. Touch platforms default double-tap on, matching old Kite's mobile initialization behavior; current selectable reactions are the five Kite quick reactions (❤️ 👍 😂 😮 😢). Arbitrary emoji/sticker selection remains a parity task.
3. Added passiveDoubleTapReaction: a non-consuming PointerEventPass.Final observer scoped to the message-content surface (not the whole event row), so existing reactions/read receipts are outside its hit area. It never waits before allowing the normal tap path, rejects motion beyond touch slop, long presses and multi-touch, then routes valid second taps through Revenge's existing asynchronous Action.Event.ToggleReactionKey / Matrix timeline toggle rather than adding a new reaction stack.
4. Performance review caught an avoidable hot-path cost before commit: ScPref.value() creates collectAsState, so the two new preferences are collected once at the conversation-list level and passed as plain values through ConversationItemRow/EventRow instead of creating two extra preference collectors for every visible message row.
5. Build proof on Glass with JDK25: baseline :androidApp:assembleDebug completed successfully including Matrix Rust arm64 FFI; after the gesture changes :preferences:compileAndroidMain + :composeApp:compileAndroidMain passed, then a full :androidApp:assembleDebug passed. APK: androidApp/build/outputs/apk/debug/androidApp-debug.apk; merged manifest package: app.kite.revenge.debug.
6. Installed that isolated debug APK on the Samsung S25 (SM-S931B) and verified both app.kite and app.kite.revenge.debug remained installed side by side. MainActivity launched successfully (am start -W, process alive) and the collected app error log contained no fatal exception. The phone was locked when UI hierarchy was sampled, so this run does **not** claim visual onboarding or double-tap functional verification. No account was imported, no Matrix login/state was changed, and the debug app was force-stopped after the smoke test.
7. No 120 Hz/JankStats benchmark or logged-in large-room comparison yet. Haptic/reaction-burst polish, designed reaction glyphs, rich quick-reaction popup and full reaction picker remain pending.

## Changes so far — third implementation session, 2026-10-14

1. Re-read the original Kite message_more_menu_test.dart, reaction_glyph_test.dart, and message_reaction_gesture_test.dart before changing the native action surface.
2. Replaced the extra **Quick reactions** submenu with a native compact action row directly in the first message context menu. The five current Kite reactions (❤️ 👍 😂 😮 😢) are now one tap away after long-press instead of requiring a second submenu.
3. Added a reusable ContextMenuActionRowEntry rather than hard-coding reaction UI into the menu renderer. Each compact action still dispatches through KeyboardActionHandler.handleContextMenuEntry and Action.Event.ToggleReactionKey, so reaction add/remove behavior stays on Revenge's existing Matrix path.
4. The row marks a reaction as selected when the current Matrix session is already among that reaction's senders. Tapping a selected reaction invokes the same toggle action, so it removes the reaction rather than creating a parallel state path.
5. Compact buttons use 44dp native Surface targets, selected/unselected Material container colors, and explicit accessibility labels/selected semantics. No new preference/state collectors, animations, or per-frame gesture work were added.
6. Validation on Glass with JDK25: git diff --check PASS; :composeApp:compileAndroidMain PASS after the initial implementation and again after the accessibility fix; full :androidApp:assembleDebug PASS. The isolated debug APK remains androidApp/build/outputs/apk/debug/androidApp-debug.apk. This run did not reinstall or alter the production app.kite package.
7. Still pending for reaction-surface parity: Kite's custom rounded heart/thumb glyphs, painted face glyphs, burst polish, arbitrary emoji/sticker selection for the configured double-tap reaction, and logged-in on-device interaction/performance verification.

## Feature parity inventory (Flutter reference)

Use `git show 4c517c66b` in old Kite, and inspect `lib/pages/chat/events/message.dart`, `message_reactions.dart`, `chat_event_list.dart`, `chat_input_row.dart`, `chat_view.dart`, `chat_list_view.dart`, `chat_list_search_bar.dart`, `chat_app_bar_title.dart`, and `lib/widgets/chat_settings_popup_menu.dart`. Tests: `test/message_reaction_gesture_test.dart`, `test/message_more_menu_test.dart`, `test/reaction_glyph_test.dart`. The port must preserve behavior, not copy Dart UI code:

- [ ] **Fast double-tap to configured reaction**, without delaying the first single tap; tap/long-press and swipe-to-reply remain independent. Native passive implementation is compiled and installed; logged-in on-device gesture verification plus arbitrary reaction selection are still pending.
- [x] Initial native quick reaction action menu (❤️ 👍 😂 😮 😢), not yet equivalent to the rich popup.
- [ ] Native horizontal quick-reaction strip is implemented in the long-press action surface with active/toggle-off state and Matrix permissions; visual glyphs (rounded Material heart / yellow thumbs up / custom painted laughing, surprised, sad faces; emoji fallback), optional burst and the full emoji/sticker picker remain pending.
- [ ] Selection-mode behavior: single tap selects only when selection is active, otherwise instant ripple; long press opens action surface with More, Select, Copy, Edit, Reply, reactions, etc. `test/message_more_menu_test.dart` validates details.
- [ ] Swipe-to-reply and responsive message interactions, composer/input toolbar & attachment picker parity.
- [ ] Chat-list, search, room headers, message bubbles, spacing, settings, account switching, dark mode and edge-to-edge layout matching Kite without Revenge's default power-user complexity.
- [ ] Notification quick reply, notification actions/copy code, unread state, search, room hide action, media, links, attachments, encryption, threading, profiles, account switching parity.
- [ ] Dedicated debug/perf build with independent app state, on-device install and logged functional/performance evidence.
- [ ] Compare Revenge original vs native Kite on same Samsung and representative large Matrix conversations; find regressions and correct them before considering replacing Flutter Kite.

## Build prerequisites / handoff

- Glass has SDK android-37.0, multiple Android NDK versions, rustup Android targets including arm64 and java-27-openjdk alongside default JDK17. Revenge builds are now proven with JDK25; JDK27 was tested and rejected by this Gradle stack (Unsupported class file major version 71).
- Rust SDK git submodule `matrix-rust-sdk` **initialized** at pinned revision `128049fd3b183f059fb76402c82ce56ba7ddcd37`. JDK25 and `cargo-ndk` 4.1.2 installed on Glass; keep system default Java17 unchanged and set `JAVA_HOME=/usr/lib/jvm/java-25-openjdk` per Gradle command.
- `JAVA_HOME=/usr/lib/jvm/java-25-openjdk ANDROID_HOME=/opt/android-sdk ./gradlew help --no-daemon` PASS. `:androidApp:processDebugResources` PASS (compiled Kite Android branding). JDK27 was rejected with `Unsupported class file major version 71`.
- Full Android debug build is now proven with JDK25: :androidApp:assembleDebug completed BUILD SUCCESSFUL, including the pinned Matrix Rust arm64 FFI build. The isolated APK is androidApp/build/outputs/apk/debug/androidApp-debug.apk with package app.kite.revenge.debug; it has been installed side by side on the Samsung S25 without replacing app.kite.
- Private GitHub fork: `https://github.com/brandonp2412/Kite-Revenge`, `origin/main`; official `upstream/main` retained. Git history unshallowed before pushing. First branded quick-actions commit `89ddcee` pushed.
- On-device Android development must never replace `app.kite`. Original app remains under its prior signing key; installing build with different key under original ID would damage continuity. For any ADB operations, identify devices and package before using one. Do not uninstall production app. Keep Android debug/perf app separate.
- Workflow each run: inspect status; read this ledger; implement a coherent bounded feature slice; test; record exact evidence; commit validated progress; arrange a persistent remote/private repository when appropriate; do not claim parity prematurely.
