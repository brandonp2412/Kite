> Kite is the public app name and `app.kite` is its Android ID as of 2026-10-16. Older references to `app.kite.revenge.debug` below describe the previous test build.

# Kite Native (SchildiChat Revenge) migration

## Goal and constraints

The user reports that SchildiChat Revenge has essentially zero perceptible UI lag on Samsung Galaxy S25, but finds its interface ugly/confusing. Use Revenge's native Kotlin/Jetpack Compose + Matrix Rust SDK architecture as the foundation for Kite. Reproduce **Kite's existing icon, visual style, and custom chat/reaction features**, and simplify navigation without slowing frame rendering. The original Flutter Kite source at `~/.archived/kite` is retained read-only for feature reference.

- This repo: `~/kite` on **Glass**; upstream `https://github.com/SchildiChat/schildi-revenge` at original clone `cdc162f` (GPL-3.0). Preserve upstream attribution and COPYING/LICENSE terms.
- Archived Flutter Kite: `~/.archived/kite`, historical app ID `app.kite`, source version `6bdb9823f`. **Read only**; do not edit, reset or uninstall any installed legacy app.
- Public native Kite app ID: `app.kite`. Older local PerfDebug installations use `app.kite.revenge.debug` with separate data. **Do not uninstall or reset either installation.** Preserve Matrix sessions.
- Historical note: a `kite-revenge-native` Prompta job was configured on Nox on 2026-10-14. No matching job is currently registered; do not assume it is running.
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

## Changes so far — fourth implementation session, 2026-10-14

1. Finished a broader native reaction/action slice rather than another isolated menu tweak. Added a shared KiteReactionGlyph renderer based on the original Flutter Kite reaction palette/treatment: rounded heart, yellow thumbs up/down, and native Canvas versions of the laughing, surprised and sad faces, with existing emoji/MXC fallback preserved.
2. Wired the shared renderer into both the compact long-press quick-reaction row and ordinary timeline reaction bubbles. This keeps the visual treatment consistent without introducing new Matrix state, collectors, or reaction storage; all add/remove operations still use Revenge's existing Action.Event.ToggleReactionKey / Matrix timeline path.
3. Expanded the long-press quick row to five direct toggles plus a sixth Add Reaction action. The sixth action enters Revenge's existing Action.Event.ComposeReaction flow instead of creating a parallel picker/state stack.
4. Made DraftType.REACTION act as an immediate full reaction browser: an empty reaction composer now exposes standard emoji plus room custom-emote suggestions before the user types a prefix, and clicking a suggestion from an empty draft works. Existing lazy suggestion rendering is retained.
5. Fixed an adjacent composer bug discovered while implementing the picker: onConfirmSuggestion previously moved the cursor one character past emoji/custom-emote insertions even when no trailing space was appended. Cursor movement now matches shouldAppendSpace.
6. Performance pass on the new full browser: standard emoji suggestion objects are lazily cached once per provider, opening an empty reaction picker reuses that list, and the empty-prefix path skips the otherwise pointless full-list sort. Filtering/suggestion generation remains on the existing Dispatchers.IO flow, while the UI remains Revenge's lazy suggestion list.
7. Validation on Glass with JDK25: git diff --check PASS; :composeApp:compileAndroidMain PASS; final :androidApp:assembleDebug PASS. The generated APK badging is still app.kite.revenge.debug, label Kite, target SDK 37.
8. Reinstalled only app.kite.revenge.debug on the connected Samsung S25. Before and after installation, both app.kite and app.kite.revenge.debug were present. am start -W returned Status: ok, the debug process was alive (pid 14266), filtered AndroidRuntime output contained no fatal exception, and only the debug package was force-stopped afterward. The handset was locked/dozing, so this is launch/safety smoke evidence only, not visual, logged-in reaction, or frame-time proof.
9. Remaining reaction parity: a dedicated arbitrary-emoji selector for the Double-tap reaction setting (the setting still exposes the five quick presets), any deliberate reaction burst/haptic polish, and logged-in side-by-side interaction/JankStats testing on large histories.

## Changes so far — fifth implementation session, 2026-10-14

1. Moved off reaction-only work and completed the native message-selection/action slice against the original Flutter behavior in test/message_more_menu_test.dart, message.dart, and the selection/action code. Long-press exposes explicit Select/Deselect; a normal tap remains the ordinary immediate message action until selection mode exists; once active, tapping selectable messages toggles them and back clears the selection.
2. Added a native selection gutter/highlight and bottom selection action bar using stable Matrix event/transaction IDs rather than a parallel message-state model. Reply and Edit reuse the existing Revenge event action provider, single-message Copy reuses its existing copy action, multi-message Copy formats the live selected events in timeline order, and Delete/Redact uses the existing permission checks plus the native confirmation/redaction flow. Sticker/poll message actions were included where the native Matrix action path supports them.
3. Selection state was tightened from timeline rescans to an ID-keyed selected-item map (31933b13, 25ad91d2), and the selection redaction/confirmation path was completed in 28d53a58. Selection mode suppresses message swipes, double-tap reactions, and jump FABs so gesture meanings cannot overlap.
4. Performance work accompanied the feature slice instead of adding row-local state: swipe preferences are collected once at conversation scope, and room permissions, thread ID, fully-read state, and jump target are lifted out of visible event rows. The no-swipe/disabled path now returns before allocating drag state, decay physics, mutable offsets, or an overridden ViewConfiguration.
5. Rechecked the original Kite swipe setting (swipeRightToLeftToReply, default true) and found Revenge's touch default was reversed. Native Kite now defaults the left/end-to-start action to Reply and the opposite direction to None on touch devices, while preserving Revenge's configurable per-direction actions.
6. Validation on Glass with JDK25 after the swipe-direction/performance changes: :preferences:compileAndroidMain :composeApp:compileAndroidMain --no-daemon PASS (BUILD SUCCESSFUL, 26s), then :androidApp:assembleDebug --no-daemon PASS (BUILD SUCCESSFUL, 8s, 188 tasks). The APK remains androidApp/build/outputs/apk/debug/androidApp-debug.apk, package app.kite.revenge.debug, target SDK 37.
7. Reinstalled only app.kite.revenge.debug with adb install -r on the connected Samsung S25. The production app.kite package path was identical before/after, the debug package retained its original first-install timestamp (data preserved), and a cold MainActivity launch completed successfully in 699 ms with the Compose Inbox rendered. The debug app was force-stopped afterward.
8. The debug profile on the phone is logged in, so this session intentionally did **not** open a real room or invoke reply/react/redact actions: doing so could alter remote read/event state. Therefore selection/swipe behavior is compiled and structurally integrated but live message-row interaction and 120 Hz frame/jank parity are still pending a controlled test room/account. Do not treat the 699 ms Inbox cold-launch number as message-timeline performance parity.


## Changes so far — sixth implementation session, 2026-10-14

1. Finished the selection hot-path cleanup instead of leaving the first compiled implementation in place. Selected timeline items now use a persistent immutable map with builder-style mutation, eliminating the earlier O(loaded-room-history) rescan and avoiding whole-selection Map copies on each toggle. Reply visibility also now obeys the room's canSendMessages permission, matching Revenge's existing context action gating. Final fixes: d8d78280, 4d5dcf96, 21a2aa00.
2. Continued directly into the next user-visible parity area: composer attachments. The existing single generic picker was split into typed Camera / File / Gallery actions without creating a second attachment state path; all successful picks still feed the existing ComposerViewModel attachment flow. Android Gallery uses image/video MIME filtering, Camera uses ActivityResultContracts.TakePicture plus the existing FileProvider/cache architecture, and picker continuations remain one-at-a-time per activity.
3. Ported Kite's original plus-button attachment sheet as a native Material bottom sheet, preserving the original action order and wording: Take a photo, Upload file, Open gallery. The UI only exposes platform-supported picker kinds. Added the composerAttachments FileProvider cache path required for camera output. Commits: ae2df807, aa42f8d8, 4c4a9f46.
4. Validation on Glass/JDK25: git diff --check PASS; :composeApp:compileAndroidMain PASS; :composeApp:compileKotlinDesktop PASS; final :androidApp:assembleDebug PASS (188 tasks, BUILD SUCCESSFUL in 34s). The final APK SHA-256 was c73c3bafaf19784d6c3b6d62334bacd6b2e56120442bd596ddc42e1c6786a38d and apkanalyzer reported application ID app.kite.revenge.debug.
5. Reinstalled only app.kite.revenge.debug on the Samsung S25 (ADB serial <private-adb-device>). The production app.kite package path was identical before/after. Final cold MainActivity launch returned Status: ok in 654 ms, the process reached RESUMED, and filtered AndroidRuntime logs showed no fatal exception.
6. Performance evidence remains explicitly non-parity. The valid settled debug Inbox sample earlier in this run rendered 413 frames with p50 8 ms, p90 16 ms, p95 21 ms, p99 24 ms and 178/413 (43.1%) frame-deadline misses under injected scrolling. The phone supports 120 Hz, but the post-sample display snapshot was at 60 Hz, so this is only a regression target, not 120 Hz proof. A repeat after the final APK was invalidated by a concurrent external `adb shell am force-stop app.kite.revenge.debug`; logcat showed the explicit force-stop and no FATAL EXCEPTION, so no replacement performance number is recorded.
7. This session still did not enter a live Matrix room on the logged-in debug profile. Selection/reply/redact, swipe, and the new attachment sheet therefore have compile/device-launch evidence but not controlled end-to-end room interaction evidence. Next substantial slice: complete the remaining selection toolbar parity (Forward plus the single-message More/action surface), then exercise selection/swipe/attachment behavior in a controlled test room/account and collect trace/JankStats evidence on a large history at an actually active 120 Hz mode.



## Changes so far — seventh implementation session, 2026-10-14

1. Completed the remaining native selection/action surface rather than stopping at the first Forward compile. Selection count/close now lives in the conversation top navigation while the lower action bar stays action-focused; it covers Reply, Retry for a single failed local echo, Copy, Forward, More, and permission-gated Delete/Redact as appropriate. Retry routes through Revenge's existing `Action.Event.RetrySend`; Reply/Edit/Pin/Unpin/Download/Redact continue to use the existing event action provider rather than parallel Matrix state.
2. Added an end-to-end Forward workflow. Selection captures only stable session/source-room/event IDs, navigates to a room picker, exposes only same-session joined non-space targets, confirms before sending, and returns to the destination room after success. Actual delivery uses the Matrix Rust SDK-backed `Timeline.forwardEvent(...)` from the source room timeline rather than re-sending raw event JSON, so encrypted/media forwarding and relation handling stay in the SDK.
3. Hardened multi-message forwarding for partial failure and cancellation races: each forward request gets a monotonic operation ID, every async iteration verifies that it is still the current request, and each event ID is removed immediately after the SDK accepts it. If a later event fails, the picker remains pending with only unsent IDs, so retrying cannot duplicate messages already forwarded; cancelling cannot let a stale async batch consume a newer request. Pending forward state is collected once at Inbox scope and passed to rows; no per-row collector or duplicate room/timeline state was added.
4. Finished the single-message More sheet with Edit, Reply in thread, Pin/Unpin, Download, Message info, Report message, and Delete/Redact where applicable. Thread visibility obeys send permission; pin/unpin uses the room's native `canOwnUserPinUnpin()` permission; Report is hidden for own messages.
5. Added native Message info and Report flows. Message info shows sender, time, send status, and raw event source; potentially large raw JSON pretty-printing runs on `Dispatchers.Default` instead of blocking Compose. Reporting uses a native reason sheet plus `JoinedRoom.reportContent(...)` on `Dispatchers.IO`; selection is cleared only after the asynchronous report succeeds, preserving context on failure.
6. During integration with an overlapping migration turn, validation caught and fixed concrete merge defects instead of committing them: duplicated Report strings/actions, a changed report API call site, duplicate forward-target conditions, and a Kotlin smart-cast failure. The final More sheet contains one Report action. The worktree then remained unchanged through a full Android build.
7. Validation on Glass/JDK25 after the final concurrent selection-header/cancellation-safety edits: `git diff --check` PASS; `:composeApp:compileAndroidMain :composeApp:compileKotlinDesktop --no-daemon` PASS; focused `:composeApp:desktopTest --tests chat.schildi.revenge.model.MessageForwardTest --no-daemon` PASS, covering stale-operation replacement, partial-forward progress, and stale-clear safety; final `:androidApp:assembleDebug --no-daemon` PASS (184 tasks). No watched production source changed during the final full build. Final combined APK: `androidApp/build/outputs/apk/debug/androidApp-debug.apk`, 146,331,543 bytes, SHA-256 `67944cf48919f5dab7ea8524a777d34d60bf8661d1801d6222bd3e618725c248`; final AAPT badging reports package `app.kite.revenge.debug`, label Kite, target SDK 37.
8. Device safety evidence now covers the exact final APK hash above: `adb install -r` successfully reinstalled only `app.kite.revenge.debug` on Samsung S25 ADB serial `<private-adb-device>`, preserving debug-app data. The production `app.kite` package path was unchanged before/after install, while only the debug package path rotated. The exact final APK then cold-launched with `Status: ok`, `LaunchState: COLD`, `TotalTime: 743 ms`, and the debug process remained alive. No live room was entered and no message action was triggered during this smoke test.
9. No valid new frame-time result is claimed. Earlier in the run the handset was sleeping and gfxinfo reported zero rendered frames; waking it and entering real rooms solely to manufacture a number would risk changing live read state. Forward/report/delete and message-row interaction therefore have compile/package/launch evidence but still need controlled end-to-end verification in a dedicated test room/account before claiming behavioral or 120 Hz performance parity.
10. Next substantial slice: simplify and visually align the room list, search, and navigation surface with Flutter Kite while preserving Revenge's room-list data path and responsiveness; include controlled interaction/performance evidence when a safe test room/account is available.


## Changes so far — eighth implementation session, 2026-10-14

1. Completed the planned room-list/search/navigation simplification as a broad native slice in commit b2b0a933. The compact/mobile Inbox no longer renders Revenge's title/action bar, account-status chip row, space selector strip, space-swipe overlay, or space-filtered empty states. It now follows current Flutter Kite's structure: the room list occupies the main surface and a rounded 12dp secondaryContainer Search bar floats at the bottom above navigation insets; wide layouts keep the same search/account surface at the top.
2. Matched the current Flutter search/account control rather than preserving Revenge affordances that Kite removed. The field uses the exact Search... hint, Search → Clear behavior, a 56dp settings/account affordance with a 44dp rounded account avatar, the compact 88dp list reserve, and the extra 8dp room-list top inset. A reference re-check caught and removed an inherited native Create Room button because current Flutter Kite's search suffix is only the account/settings control.
3. Made the personal Inbox explicitly space-free at the model layer without changing the Matrix Rust room-list source. filteredRooms now combines only the existing all-room summaries, local search term and session order; spaces are excluded in both unsearched and searched states. Search/ranking was extracted into KiteInboxFilter, remains off-main on the existing Dispatchers.Default flow, preserves native room order when no query is active, and ranks case-insensitive public/private-name matches by earliest match, activity and account order. The previous selected-space / seen-invite filter inputs are no longer on this hot path.
4. Added KiteInboxFilterTest covering blank-search order + space exclusion, public/private case-insensitive matches, and match-position/activity/session-order ranking. Focused test and the complete :composeApp:desktopTest suite pass.
5. Simplified room-row visuals and hot-path state. Room avatars now use the room avatar or single DM hero plus the existing account-disambiguation badge only; bridge-protocol badges and canonical-parent-space avatar fallback were removed. This also removes the per-row spaceSummariesByKey.collectAsState() dependency that the old fallback introduced.
6. Simplified the long-press room action surface to current Kite intent: Mark read/unread, Favorite, direct Mute/Unmute, Leave, and More → Low priority where applicable. Revenge-only Open-here/Open-new-window and command-mode entries are gone, and the four-level notification submenu was replaced by one toggle that still dispatches through the existing Action.Room.SetRoomNotifications / Matrix notification path (Mentions on mute, All on unmute).
7. Device testing found and fixed a real first implementation bug before checkpoint: the Compose search field receives programmatic focus on launch, so an onFocusChanged hook incorrectly entered empty search mode and showed Clear immediately. Search activation now occurs only through text changes; a cold Inbox can retain focus without visually entering search.
8. Validation on Glass/JDK25: repeated git diff --check PASS; :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop --no-daemon PASS; focused KiteInboxFilterTest PASS; full :composeApp:desktopTest --no-daemon PASS; final :androidApp:assembleDebug --no-daemon PASS. Final installed APK is androidApp/build/outputs/apk/debug/androidApp-debug.apk, package app.kite.revenge.debug, label Kite, target SDK 37; SHA-256 4af6337e20681b4e61be23b3a1004064ca9a970e06696b738b84f1277279c809.
9. Reinstalled only app.kite.revenge.debug on the connected Samsung S25; the production app.kite remained separately installed. On-device UI checks verified: cold Inbox shows Search... and Settings with no Clear state; typing a synthetic zzzzkiteprobe query activates Clear; tapping Clear restores the empty query; the account/settings avatar navigates to Settings; nine visible room rows were present; long-press menus exposed read/unread, Favorite, Mute/Unmute and Leave; a non-favorite row exposed Show more → Low priority. No room was opened and no Matrix action was executed.
10. No new performance-parity claim is made. The handset reported the app at 60 Hz during this run. A shell-injected scroll probe produced only 19 rendered frames and was dominated by input/UI-thread latency (57.9% gfxinfo jank), so that sample is explicitly discarded as injection-limited rather than treated as either a regression or success. The prior settled Inbox sample remains the only usable regression reference until a controlled large-history run can be performed at an actually active 120 Hz mode.
11. Remaining Inbox/search parity is now narrower: Flutter Kite's global user/public-room search and any remaining room-row visual details / hide-room behavior still need porting and controlled device proof. After that, move to notification quick-reply/actions and the remaining controlled message/composer E2E work.

## Feature parity inventory (Flutter reference)

Use `git show 4c517c66b` in old Kite, and inspect `lib/pages/chat/events/message.dart`, `message_reactions.dart`, `chat_event_list.dart`, `chat_input_row.dart`, `chat_view.dart`, `chat_list_view.dart`, `chat_list_search_bar.dart`, `chat_app_bar_title.dart`, and `lib/widgets/chat_settings_popup_menu.dart`. Tests: `test/message_reaction_gesture_test.dart`, `test/message_more_menu_test.dart`, `test/reaction_glyph_test.dart`. The port must preserve behavior, not copy Dart UI code:

- [ ] **Fast double-tap to configured reaction**, without delaying the first single tap; tap/long-press and swipe-to-reply remain independent. Native passive implementation is compiled and installed; logged-in on-device gesture verification plus a dedicated arbitrary-emoji settings selector are still pending.
- [x] Native compact long-press quick-reaction row (❤️ 👍 😂 😮 😢) with active/toggle-off state, shared Kite-designed glyphs, and a sixth Add Reaction entry into Revenge's existing reaction composer.
- [x] Message reaction browsing supports immediate standard emoji + room custom-emote suggestions, including selection from an initially empty reaction draft, without a parallel Matrix state stack. A dedicated tiled/category picker and the double-tap setting's arbitrary-emoji UI remain polish/parity work.
- [ ] Selection-mode behavior: single tap selects only when selection is active, otherwise instant ripple; long press opens action surface with More, Select, Copy, Edit, Reply, reactions, etc. Selection, Retry, Forward, More/Info/Report/Pin/Thread/Download/Delete are now implemented and compiled; controlled live-room interaction proof is still pending. `test/message_more_menu_test.dart` validates details.
- [ ] Swipe-to-reply and responsive message interactions, composer/input toolbar & attachment picker parity. Camera/File/Gallery attachment selection now matches Kite structurally and is compiled/installed; controlled live composer E2E plus remaining composer/recording parity are still pending.
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

## Changes so far — ninth implementation session, 2026-10-14

1. Continued directly from the broad Inbox/search/navigation migration instead of returning to reactions. During this run an overlapping migration turn landed the main room-list slice as b2b0a933 plus its ledger checkpoint bdbf5673; the follow-on work was reconciled against that new HEAD before committing, with no reset or overwrite of concurrent progress.
2. Finished the remaining high-visibility room-row treatment against the Flutter Kite reference. Rows now use Kite-like 16dp vertical padding/minimum height, one display name instead of Revenge's public/private secondary-name presentation, and compact cached-state indicators beside the timestamp: notification-muted, low-priority, and pinned/favorite. Favorite uses a push-pin rather than Revenge's star, and low-priority uses the matching low-priority glyph.
3. Aligned the long-press favorite action with Kite wording and visuals: it now presents Pin/Unpin dynamically with the push-pin glyph while still dispatching Revenge's existing Action.Room.MarkFavorite command. The obsolete context-menu focus-id plumbing was removed. The room-row/context-menu path stays on the existing room summary state; no new per-row Matrix collector or parallel notification state was introduced.
4. Finished invite-row interaction parity without adding Matrix plumbing. The large inline Join button was removed. Tapping an invite row now invokes the existing InboxViewModel.joinRoom(...) action, respects the existing PendingAction.RoomJoin(...).isAllowed() gate, and navigates to the conversation using the same success result path that the old Join button used. Join/Reject remain available through the existing invite action surface. Live invite acceptance was deliberately not exercised because the connected debug profile is real and accepting an invite would mutate remote Matrix state.
5. Validation on Glass/JDK25 after the invite-row rewrite: git diff --check PASS; :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop --no-daemon PASS (BUILD SUCCESSFUL in 27s); final :androidApp:assembleDebug --no-daemon PASS (184 tasks, BUILD SUCCESSFUL in 8s). The final APK is androidApp/build/outputs/apk/debug/androidApp-debug.apk, 145,747,587 bytes, SHA-256 c5e70c57a757d4fea9835548be6c432316c0ec490924c8edbb954782d3a7b24d; apkanalyzer reports application ID app.kite.revenge.debug.
6. Reinstalled only that exact debug APK on Samsung S25 ADB serial <private-adb-device>. The production app.kite package path was identical before and after installation. The exact final APK cold-launched successfully (Status: ok, LaunchState: COLD, TotalTime: 671 ms), and the resulting UI hierarchy showed the Inbox with the Search... field and Settings affordance. No room was opened and no Matrix action was executed.
7. Performance evidence is still explicitly non-parity. The handset supports 120 Hz but was actively rendering at 60 Hz in this session. A warm shell-injected Inbox scroll on the exact final APK recorded 211 frames with p50 7 ms, p90 10 ms, p95 11 ms and p99 19 ms, but the same sample reported 202 high-input-latency events and 91 slow-UI-thread events, so its 44.1% modern frame-deadline-miss rate is injection-limited and is not treated as either a success or a regression. A controlled touch/JankStats or Macrobenchmark-style run at an actually active 120 Hz mode is still required before claiming the 8.33 ms target.
8. Remaining Inbox parity is now primarily global user/public-room discovery and Flutter Kite's hide-room behavior, plus controlled invite-row proof in a disposable/test account. After that, the next substantial user-visible slice is notification quick-reply/actions and the remaining controlled message/composer E2E work, followed by side-by-side 120 Hz performance comparison against stock SchildiChat Revenge.


## Hotfix / release install — 2026-10-14

1. Fixed the persistent Inbox search field reopening the Android IME. Revenge's FocusRole.SEARCH_BAR auto-requests focus by design; Kite's always-visible Inbox search now opts out of mount-time focus while retaining the SEARCH_BAR role for explicit keyboard search actions. Inbox search focus is also cleared when the search composable leaves the destination, preventing retained text-editor focus from reopening the IME when returning from a conversation.
2. Validation on Glass/JDK25: :composeApp:compileAndroidMain PASS; :androidApp:assembleRelease -PandroidAbi=arm64-v8a PASS with R8/resource shrinking; :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a PASS. The release APK is androidApp/build/outputs/apk/release/androidApp-release.apk, package app.kite.revenge, version 26.10.14, arm64-v8a only, signed with the configured Brandon Presley signing certificate and not marked debuggable.
3. Installed release app.kite.revenge on Samsung S25 ADB serial <private-adb-device>; app.kite and app.kite.revenge.debug remained installed side-by-side. Android reports versionCode=26101400, versionName=26.10.14, primary ABI arm64-v8a, and no DEBUGGABLE package flag.
4. Updated the existing app.kite.revenge.debug install with the optimized PerfDebug APK so the same focus fix is present while preserving its logged-in app data. The handset was dozing during final verification, so no claim is made that the return-from-chat IME sequence was interactively exercised after the fix; compile/package/install evidence is complete.
5. Note: the installed release artifact was built from the current worktree while the next device-local hide-room slice was still in progress and unstaged. Do not treat its APK hash as a clean-commit release artifact.

### Mobile navigation and IME follow-up — 2026-10-14

- Compact Inbox now applies IME padding to the viewport so the list and bottom search field stay visible while typing.
- Compact conversations keep a visible top navigation row in minimal mode and use a leading back arrow.
- Wide/desktop conversation navigation remains unchanged.
- Samsung test target is now original app.kite plus native app.kite.revenge.debug using the release-optimized PerfDebug variant.
- The separate app.kite.revenge install is no longer present on the device.

### Matrix send-queue encryption compatibility — 2026-10-14

- Fixed encrypted-room sends getting wedged when a verified Matrix account still has unsigned/legacy devices.
- Normal mode now uses the Rust SDK \`ALL_DEVICES\` room-key recipient strategy; explicit signed-device isolation still uses \`IDENTITY_BASED_STRATEGY\`.
- Root cause was confirmed from the Rust SDK send queue in the Tyla Meta-bridged room: \`VerifiedUserHasUnsignedDevice\` prevented the event from reaching Synapse, so the Facebook bridge was not at fault.
- Verified Matrix-to-Meta forwarding separately with a real test event and bridge message mapping on Nox.
\n

## Google Messages visual migration — tenth implementation session, 2026-10-14

1. Switched the active visual target from Flutter Kite styling to the committed Google Messages reference set in docs/design-reference/google-messages, while preserving Kite branding and the deliberate bottom-search exception. This slice was based on the pinned inbox, conversation, Material 3 overview, and dark attachment-menu captures. A live installed-Messages comparison was attempted read-only on the Samsung, but the handset later became unreachable over wireless ADB, so no live Google Messages screenshot or SMS/RCS state change is claimed.
2. Introduced a Kite-purple Material 3 tonal system across light/dark surfaces: soft background/container levels, distinct incoming/outgoing message surfaces, near-black dark background, and a purple-tonal outgoing bubble. Increased app-bar height/icon scale, made conversation avatars circular, tightened timeline gutters/group spacing, moved message bubbles to 20dp corners with 14x9dp content padding, and reduced date separators to secondary label treatment.
3. Reworked the Inbox toward the Google Messages hierarchy without moving search from the bottom. Room avatars are circular; rows are denser; names/previews/timestamps use unread-aware weight/color; previews are single-line; unread badges are smaller. Removed the redundant Revenge top search and duplicate settings action so the persistent bottom search/account pill is the single search/account surface. The bottom control is now a 28dp-radius tonal capsule with a circular account avatar and localized Search hint.
4. Kept the Inbox hot path lean while adding the unread hierarchy: the three unread-count preferences are now collected once at Inbox scope and passed as plain values to visible rows rather than being collected independently in every row. No new per-row Matrix state or animation was introduced.
5. Reworked the conversation composer as a 56dp tonal 28dp-radius input capsule with a separate 48dp circular send action, persistent attachment affordance for ordinary text drafts, brand-accent cursor/send treatment, and a rounded tonal reply state. The existing camera/file/gallery attachment flow now renders as a Material 3 bottom sheet with large rounded action tiles instead of Revenge's vertical menu; the underlying picker/ViewModel/Matrix flow is unchanged.
6. Continued the same visual system through interaction surfaces: quick-reaction buttons are 48dp tonal targets with brand-accent selected state, timeline reaction chips use a subtler accent fill/border, and all existing Kite reaction glyphs/toggle behavior remain on Revenge's Matrix action path.
7. Validation on Glass/JDK25: git diff --check PASS; :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop --no-daemon PASS twice after the visual/refactor work; complete :composeApp:desktopTest --no-daemon PASS (55 tasks); final release-like :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon PASS with R8/resource optimization (279 tasks). The built APK is androidApp/build/outputs/apk/PerfDebug/androidApp-PerfDebug.apk, 107,869,460 bytes, SHA-256 3d47cd86cbc5daacb0d3294eb83e4742e400bca86ec8a44fe8f45ce6a0a9d3fd; apkanalyzer reports application ID app.kite.revenge.debug, target SDK 37, and debuggable=false.
8. Device QA is a concrete blocker for this checkpoint rather than an implied success: <private-adb-device> currently reports offline, reconnect attempts time out, and even ICMP to that address times out. The PerfDebug APK was therefore not installed this session and there is no side-by-side handset screenshot, keyboard/inset check, live room interaction, or 120 Hz frame-time claim for these visual changes. app.kite was not touched.
9. Preserved the pre-existing unfinished device-local hide-room changes in InboxViewModel.kt, AppStateStore.kt, and strings.xml; they were not reset, folded into this visual slice, or staged with it. Next visual work should begin with Samsung side-by-side QA when the handset is reachable, then iterate the remaining conversation action/selection surface, settings/account rows/dialogs, dark-theme/accessibility mismatches, and controlled 120 Hz large-history measurement.


## Google Messages visual migration — eleventh implementation session, 2026-10-14

1. Continued the Google Messages visual pass as a cohesive interaction/settings slice, using the committed 03-material3-settings.jpg, 05-material3-chat.webp, and 06-dark-attachment-menu.webp references. No Google branding/artwork was copied and the Inbox bottom-search exception remains unchanged.
2. Restyled message long-press/action surfaces without changing Matrix behavior. The quick-reaction/action row now uses larger 52dp tonal targets, Material 3 primary-container selection, stronger spacing/labels, and neutral on-surface action text; the selection toolbar is a rounded surfaceContainerHigh capsule with 56dp actions; the More sheet uses rounded tonal rows/icon wells with a distinct error-container treatment for destructive actions.
3. Carried the same system into message details/reporting. Message Info uses a low tonal sheet, rounded info/source cards, secondary labels and body-value hierarchy. Report Message uses the same sheet tone, title hierarchy, large rounded reason field, and pill-shaped report action. All existing edit/thread/pin/download/info/report/delete/copy/reply/forward callbacks remain on their previous ViewModel/Matrix pathways.
4. Restyled shared settings/account surfaces instead of one-off screens. Preference rows now use rounded low-tonal containers with neutral onSurface / onSurfaceVariant hierarchy; category headers use Messages-like section spacing without divider clutter; the settings app bar is forced visible. Existing-account and add-account sections are grouped into rounded surfaceContainerLow cards with calmer section labels, and account navigation is explicitly visible on compact layouts. No account/session state model was duplicated.
5. Preserved performance characteristics: the slice adds only static Material color/shape/layout values to existing composables, with no new animations, Matrix collectors, flows, per-row state subscriptions, or blocking work. The existing off-main message-source formatting remains unchanged.
6. Validation on Glass/JDK25: git diff --check PASS; :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop --no-daemon PASS; full :composeApp:desktopTest --no-daemon PASS (55 tasks); final :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon PASS with R8/resource optimization (279 tasks). Final APK androidApp/build/outputs/apk/PerfDebug/androidApp-PerfDebug.apk is 107,853,076 bytes, SHA-256 a66c9801f9a50fb50b058388600ded43e5fb58f7a1dff2d0af90464a9f532439; aapt2 reports package app.kite.revenge.debug, label Kite, target SDK 37, arm64-v8a; apksigner verifies the configured signing certificate.
7. Samsung S25 ADB serial <private-adb-device> became reachable again. Installed only the verified PerfDebug artifact with adb install -r; Android reports app.kite.revenge.debug versionName perfdebug-26.10.14, preserving the existing debug package/data. No app.kite.revenge release package was installed or recreated.
8. A read-only current Google Messages comparison was attempted after reconnecting. com.google.android.apps.messaging/.ui.ConversationListActivity is the installed Messages inbox activity, and scrcpy was kept in screen-off mode, but the device is securely locked; the captured stream is the lock screen. I did not bypass the lock, enter an SMS/RCS conversation, or mutate Messages state. Therefore this checkpoint does not claim a live same-screen visual comparison, keyboard/inset proof, live Matrix room action proof, or a new 120 Hz frame-time result.
9. Preserved the pre-existing unfinished device-local hide-room changes in InboxViewModel.kt, AppStateStore.kt, and strings.xml unstaged and untouched by this visual commit. Next substantial visual slice should start with unlocked Samsung screenshot QA, then iterate any observed inbox/conversation/settings mismatches and finish dark-theme/accessibility plus controlled large-history 120 Hz measurement.


### Google Messages bubble-width correction — 2026-10-14

- Follow-up from Zeus exposed that the remaining Revenge message-width defaults were still too conservative on phone: at the S25's 360dp logical width, the old 12dp timeline gutters + 48dp opposite margin + 48dp avatar/12dp avatar gap reserved 132dp and limited long bubbles to about 228dp (63% of the screen), creating a visually centered column.
- Updated the Google-Messages-style phone defaults to a 16dp opposite margin, 32dp sender avatar, 8dp avatar gap, and 8dp timeline gutters. The same long-message case can now use about 288dp (80%) while preserving a clear opposite-side gutter and group-sender avatar lane.
- This is a global conversation-layout correction, not a Zeus special case; short bubbles retain natural wrap-content sizing and Matrix message/action behavior is unchanged.
- Validation: git diff --check PASS; Android + desktop compile PASS; full :composeApp:desktopTest PASS; arm64 :androidApp:assemblePerfDebug PASS. Verified APK SHA-256 935fb7cdbb9ff4405471e17bfd9c2b32fe726a2dfa167fc69acf57f4d89af102, package app.kite.revenge.debug. Reinstalled successfully over the existing Samsung debug package with adb install -r.

## Google Messages visual migration — twelfth implementation session, 2026-10-14

1. Continued the conversation-screen slice against the committed docs/design-reference/google-messages/05-material3-chat.webp baseline, with the current Google Messages rounded thread-container treatment as the public cross-check. The deliberate Kite bottom-search exception is unchanged. A live Messages comparison was not forced because the connected Samsung was behind secure keyguard; no SMS/RCS conversation, read state, or Messages setting was touched.
2. Fixed the room-specific “chat floating in the middle” layout cause rather than applying a Zeus-only offset. Revenge always placed the sender-avatar reservation before incoming content, so two-member bot/bridge rooms could look like group chats even when they were visually one-to-one. Two-member rooms now hide timeline sender avatar/name chrome even when m.direct is absent, while true multi-member rooms retain it.
3. Propagated that one room-level showSenderDetails decision through the existing timeline row hierarchy as a plain Boolean. Incoming message layout, reaction chips, and thread metadata all use the same decision, so a compact one-to-one room cannot move its bubble edge while leaving reactions/thread hints stranded in the old avatar lane. No new Matrix collector, per-row flow, duplicated room state, or hot-path allocation source was introduced.
4. Preserved the preceding 80%-class bubble-width budget instead of globally widening every chat: when one-to-one sender chrome is hidden, its avatar-width reservation is transferred to the far-side margin. This moves incoming 1:1 bubbles to the proper edge without changing the established long-bubble cap; outgoing and group-room width budgets remain intact. Added a 28dp rounded-top surfaceContainerLow thread surface plus matching composer tone below the app bar, following Google Messages' Material 3 layered conversation treatment without per-message effects or animation.
5. Added ConversationScreenLayoutTest as a regression guard: unknown/one/two-member rooms suppress timeline sender chrome, while rooms with three or more joined members retain it. Nested reply content explicitly keeps sender identity.
6. Final source validation on Glass/JDK25 after formatting: git diff --check PASS; :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop :composeApp:desktopTest --no-daemon PASS (87 tasks, BUILD SUCCESSFUL in 25s). The earlier focused ConversationScreenLayoutTest run also passed. Final release-like :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon PASS (275 tasks, BUILD SUCCESSFUL in 57s); APK size 107,853,076 bytes, SHA-256 a7f2e02e5937596908fbb520d0cdc6f81ee9bcf0735f4bea9b3de456eea19535, package app.kite.revenge.debug.
7. Device/package safety was rechecked before and after installation: app.kite.revenge was not installed or recreated, and only app.kite.revenge.debug was updated with adb install -r, preserving dataDir /data/user/0/app.kite.revenge.debug. The final artifact launched successfully behind secure keyguard (Status: ok; process PID 26317 remained alive), and the recent 300-line log sample contained no FATAL EXCEPTION. The connected Samsung remained securely locked during visual QA, so this session does not claim side-by-side Zeus/direct/group screenshots, keyboard/inset proof, or a 120 Hz frame-time result. That remains the next device-validation step rather than an inferred parity claim.
8. Preserved the pre-existing unfinished hide-room changes in InboxViewModel.kt, AppStateStore.kt, and strings.xml; they remain separate from this visual slice. Next substantial slice: on an unlocked Samsung verify Zeus, a normal direct room, and a real multi-member room side by side against Messages, then iterate grouped bubble geometry/media/timestamp placement plus composer keyboard/insets and dark mode before collecting controlled 120 Hz large-history evidence.

## Google Messages visual migration — thirteenth implementation session, 2026-10-14

1. Continued the conversation-screen pass using the committed docs/design-reference/google-messages/05-material3-chat.webp baseline and a current public Google Messages Material 3 conversation cross-check. The pinned reference remains the stable design baseline, Kite branding remains intact, and the deliberate bottom-search exception is unchanged.
2. Checkpointed the preceding direct-room layout correction as 3f8e56b3 (Align direct-room conversation layout with Messages), then completed grouped message-run geometry in 0ea633db (Group conversation bubbles like Google Messages). Standalone bubbles keep 20dp corners; consecutive same-sender messages connect with 6dp inner corners on the leading edge for incoming messages and trailing edge for outgoing messages. Previous/next grouping is derived from the existing adjacent timeline items and per-message profile without adding Matrix collectors or row-local state. Media-only image/video bubbles inherit the same grouped shape, while reply/caption media keeps its deliberate split geometry.
3. Reduced timestamp/date metadata weight throughout the same surface: status overlay padding/icons/typography are smaller, floating-date treatment is a rounded low-tonal pill, and successful routine messages no longer carry an always-visible in-bubble timestamp. Edited, sending, failed-send and Matrix security/shield states remain visible and retain their timestamp when rendered, preserving actionable Matrix status rather than blindly copying an SMS UI.
4. The unlocked Samsung side-by-side exposed the timestamp mismatch and then caught a real regression before checkpoint completion. The first timestamp-suppression build let TimestampContent emit no child while the smart TimestampOverlayLayout still assumed a second measurable, causing an IndexOutOfBoundsException in Zeus. The final 33f8eea6 (Quiet routine message metadata like Messages) makes the layout explicitly support a missing overlay by measuring/placing content alone. Android + desktop compile and the full desktop test suite pass after that fix.
5. Added MessageBubbleShapeTest covering the full-radius standalone case and the incoming/outgoing grouped-corner orientation. Final source validation on Glass/JDK25: git diff --check PASS; :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop :composeApp:desktopTest --no-daemon PASS after the crash fix. The existing conversation-layout regression coverage also remains green.
6. Kept the release-like device artifact isolated from the unfinished hide-room changes by building from a detached clean worktree at final commit 33f8eea6. The final :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon build passed with R8/resource optimization. Validation-time APK was 107,853,016 bytes, SHA-256 3dc685710c9cd8f1e769d4c3988f58ad193604e4b38a95d9ffd9ff3bd08872b3; AAPT reports package app.kite.revenge.debug, label Kite and arm64-v8a native code. The detached validation worktree was removed after the exact artifact was installed and its hash recorded.
7. Device/package safety was verified before installation and the exact final APK was installed only with adb install -r over app.kite.revenge.debug; app.kite.revenge was not installed or recreated. The final build cold-launched successfully (Status: ok, LaunchState: COLD, TotalTime: 173 ms). Re-entering the same Zeus conversation that crashed the intermediate build kept Kite in foreground and rendered the cleaned-up timeline; the final process log sample contained no FATAL EXCEPTION or ANR marker.
8. Visual QA on the unlocked Samsung now covers both the Inbox and Zeus. The Inbox retains Kite's bottom rounded Search/account capsule with the Messages-style row hierarchy. Zeus now uses the full conversation surface instead of a centered sender lane, same-sender runs visibly connect through the grouped corners, routine per-message timestamps are gone, and the composer remains anchored above the navigation area. A direct side-by-side with the pinned Google Messages chat capture was used to drive the timestamp cleanup. No SMS/RCS message was sent, read state intentionally altered, or Google Messages setting changed for this comparison.
9. A passive final dumpsys gfxinfo app.kite.revenge.debug snapshot recorded 123 rendered frames, p50 5 ms, p90 5 ms, p95 14 ms, p99 53 ms, 5/123 modern janky frames (4.07%), zero missed-vsync events and no slow bitmap/draw-command counts. This is only a smoke/performance snapshot: the sample has 98 high-input-latency events, an active injected-scroll benchmark was blocked twice by the device-control safety layer, and there is still no valid 120 Hz or stock-Revenge side-by-side performance-parity claim.
10. Preserved the separate unfinished hide-room changes in InboxViewModel.kt, AppStateStore.kt, and strings.xml unstaged and outside all visual commits. Next substantial visual slice: exercise composer IME/inset behavior, reply/edit state and attachment presentation against the current Messages reference on-device; then finish dark-mode/accessibility and remaining selection/reaction/action-surface consistency before a controlled 120 Hz large-history comparison against stock SchildiChat Revenge.

## Google Messages visual migration — fourteenth implementation session, 2026-10-14

1. Continued the conversation interaction slice against the pinned Google Messages references and a read-only pass through the current installed Google Messages inbox on the Samsung. The live inbox still measures at roughly 80dp per row with ~52dp avatars and 16dp outer gutters at the device's 3.0 density. No SMS/RCS thread was opened, sent, archived, deleted, marked, or otherwise mutated. The deliberate Kite bottom-search exception remains unchanged.
2. Rebuilt message long-press presentation around the current Google Messages hierarchy without removing Matrix capabilities. Message context menus now use a dedicated rounded extra-large Material 3 tonal surface, and the existing quick-reaction controls render as a compact unlabeled 48dp row. Common actions stay directly visible: Reply, contextual Edit, Forward, Copy, Pin/Unpin, attachment Download, Delete, Select/Deselect, Message info, then Show more.
3. Kept the deeper Matrix actions rather than deleting them to match an SMS client. Show more preserves jump-to-reply, thread navigation, explicit reaction action, reaction/read-receipt inspection, sender details, public/private/read-marker controls, poll actions, developer actions, and command mode. Forward uses the existing MessageForward prepare/set path; Pin/Unpin dispatches the existing Action.Event commands; Message info reuses the existing MessageInfoSheet.
4. Preserved the hot path while plumbing the new actions. ConversationScreen derives one remembered pinned-event-id set from the existing room info and passes plain booleans/callbacks through ConversationItemRow/EventRow. There are no new per-row Matrix collectors, flow subscriptions, duplicated timeline state, blur/RenderEffect passes, or new animations. The current Messages background-blur treatment was deliberately not copied because Kite's 120 Hz frame budget takes priority over a cosmetic effect.
5. Source validation on Glass with JDK 25 and the Android SDK: git diff --check fbb62697..00df3a2e PASS; :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop --no-daemon PASS (BUILD SUCCESSFUL in 27s). A clean detached worktree at 00df3a2e initially lacked the matrix-rust-sdk submodule; after initializing the pinned submodule revision, :composeApp:desktopTest --no-daemon --console=plain PASS (51 actionable tasks, BUILD SUCCESSFUL).
6. Built the release-like artifact from that clean detached worktree. The first package attempt hit a generated merged_native_libs directory deletion race after the Rust release library completed; clearing only that generated intermediate and rerunning produced :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon PASS (275 actionable tasks, BUILD SUCCESSFUL in 9s on the packaging rerun). Final APK size 107,869,400 bytes, SHA-256 d7cc1f84fb8776b0acfdff3049717ca5b1032006fcce2db3b96c660bd29647c1; AAPT reports package app.kite.revenge.debug, label Kite, version perfdebug-26.10.14, native-code arm64-v8a.
7. Installed only that exact PerfDebug APK with adb install -r on Samsung S25 serial <private-adb-device>. Android retained the original app.kite.revenge.debug firstInstallTime/dataDir and updated only that package. The app start command returned Status: ok and dumpsys recorded no ANR since boot; no production app.kite install, data, login, or package operation was targeted.
8. Interactive long-press QA is the explicit remaining blocker for this checkpoint. The Samsung was unlocked for the initial read-only Google Messages inbox measurement, but moved to secure keyguard/screen-off before the final Kite interaction pass. I did not bypass the lock. Therefore this session does not claim that the new reaction/action popup was visually exercised on-device, nor does it claim a new 120 Hz frame-time result or performance parity with stock Revenge.
9. Promoted the five focused implementation commits through 00df3a2e to private-fork main after compile/test/package verification. The unrelated hide-room edits in InboxViewModel.kt, AppStateStore.kt, and strings.xml remain unstaged locally and outside these commits. Next substantial slice: unlocked-device long-press side-by-side QA first, then composer reply/edit + attachment sheet + IME/inset parity and dark-theme/accessibility cleanup, followed by controlled 120 Hz large-history measurement.

## Google Messages visual migration — fifteenth implementation session, 2026-10-14

1. Reworked the open-chat composer against the pinned Google Messages conversation reference. The main field remains a 56dp/28dp tonal capsule but is now vertically centered, uses a clean Message placeholder instead of exposing the current Markdown format in normal text/edit/caption modes, uses a smaller 24dp attachment glyph, replaces the old animal sticker icon with a Messages-like emoji face, adds a direct gallery affordance inside the capsule, and keeps the separate circular send action at 46dp. Attachment, sticker/reaction and send behavior still uses the existing ComposerViewModel/Matrix paths.
2. Reworked the open-chat search treatment. Active search now uses a rounded 28dp surfaceContainerHigh search capsule with leading search icon, placeholder text and no floating Material text-field label/underline. The normal avatar is hidden while search is active so the top bar does not retain the old Revenge avatar + rectangular search collision.
3. Made the top direct-chat identity useful. For a one-to-one room with a single hero, the top avatar falls back to that hero's avatar when the room avatar is absent, and both avatar and title navigate to Destination.UserDetails for that person. Multi-member rooms continue to open RoomDetails.
4. Removed normal-chat verification clutter. Per-message MessageShield verification/authenticity indicators are no longer surfaced, the sticky identity-state warning/acknowledge block was removed from the conversation screen, and PinViolation/VerificationViolation warning icons are no longer shown beside the name on UserDetails. The positive Verified indicator remains.
5. Removed Matrix/server-event noise from the visible timeline. Room membership, profile-change, state and unknown state events are skipped at ConversationItemRow before spacing/actions are rendered, the virtual RoomBeginning marker is hidden, and the sticky RoomUpgrade row was removed from the ordinary conversation surface. Actual user messages/media/polls/errors and day/read/typing affordances remain on their existing paths.
6. Validation on Glass/JDK25: git diff --check PASS; :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop --no-daemon PASS; full :composeApp:desktopTest --no-daemon PASS. Commit 304b561a contains only this conversation/composer/header slice; the separate unfinished hide-room changes remain unstaged.
7. Built from a detached clean worktree at 304b561a so unrelated unstaged files could not enter the device artifact. Final :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon PASS after clearing one stale partial APK packaging output. Final APK: 107,853,016 bytes, SHA-256 5453c3f27497bad12451029f747912f72d2ee0ac3f50dea1d61d145c73dd9554; AAPT reports package app.kite.revenge.debug, label Kite, arm64-v8a.
8. Installed the exact artifact with adb install -r over app.kite.revenge.debug. app.kite.revenge was not installed or recreated. The phone had NotificationShade in foreground after installation, so this run deliberately did not steal focus to force screenshot/IME interaction. The build is installed for normal inspection; on-device composer/search/profile-tap visual QA remains the immediate follow-up.


## Google Messages visual migration — sixteenth implementation session, 2026-10-14

1. Continued the open-conversation composer slice from 304b561a using the pinned docs/design-reference/google-messages/05-material3-chat.webp and 06-dark-attachment-menu.webp references, then cross-checked the attachment launcher against current public Google Messages screenshots. The current Messages launcher uses compact icon-only rounded controls with labels below; Kite now follows that presentation for the Matrix actions it actually supports instead of inventing unsupported Google actions. The deliberate inbox bottom-search exception is unchanged.
2. Integrated transient compose state into the same 28dp rounded input surface instead of stacking separate Revenge blocks above it. Reply mode now renders its label, replied-to content and compact clear control inside the composer capsule; Edit/Edit caption get an explicit integrated mode header and always-visible exit control. Existing reply/edit state and send behavior still route through the existing ComposerViewModel/DraftValue pathways.
3. Integrated attachment preview into the composer surface. Image/video previews are bounded to a compact 72dp minimum / 128x96dp maximum presentation, generic/audio attachments retain their existing content renderers, and the remove action is a compact 36dp control. The attachment chooser now uses a low-tonal 32dp-top-radius sheet with Camera/File/Gallery shown as 68x56dp rounded icon controls with labels beneath.
4. Added explicit IME handling to the composer-capable conversation root without adding Matrix state. A concurrent adjacent follow-up then refined that integration through 703f000c and cfbe448d: Android system navigation is transparent edge-to-edge with Samsung contrast enforcement disabled, composer-side safe drawing excludes the permanent bottom inset, and the composer gets a calculated bottom gap of navigation-bar + 12dp when the IME is closed or 12dp when the IME is open. Composer horizontal gutters also use the shared window padding. This avoids stacking safe-area/IME padding while keeping the input clear of Samsung three-button navigation.
5. Source validation was rerun on the final integrated revision cfbe448d in a clean local validation clone with JDK 25 + Android SDK: git diff --check for this session's source changes PASS; :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop --no-daemon PASS (BUILD SUCCESSFUL in 28s); full :composeApp:desktopTest --no-daemon PASS (BUILD SUCCESSFUL in 9s). The main reply/edit/attachment implementation is commit de91dee7; 703f000c and cfbe448d are the subsequent navigation/inset refinements now included in the validated integration point.
6. Preserved the separate unfinished hide-room changes exactly. SHA-256 checks still match their pre-run byte snapshots for InboxViewModel.kt (cdaf2fb2...394d7), AppStateStore.kt (75718718...47673), and strings.xml (dafd5af2...30b4a); they remain unstaged. Because Glass rejected the usual detached linked-worktree validation path, packaging used a fresh local clone and pinned matrix-rust-sdk revision 128049fd3b183f059fb76402c82ce56ba7ddcd37.
7. Release-like package validation from final cfbe448d: :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon PASS. Final APK /home/brandon/worktrees/kite-revenge-validate-de91dee7-clone/androidApp/build/outputs/apk/PerfDebug/androidApp-PerfDebug.apk is 107,853,016 bytes, SHA-256 7a92eac67935f1ebb724bdd709dadfb0d4f8e6fa9ad5eb087d6251f943f6bd06; AAPT reports package app.kite.revenge.debug, label Kite, version perfdebug-26.10.14, target SDK 37 and native-code arm64-v8a.
8. Installed only that exact final artifact on Samsung S25 serial <private-adb-device> with adb install -r. Android kept dataDir=/data/user/0/app.kite.revenge.debug and firstInstallTime=2026-10-14 11:55:12 while lastUpdateTime advanced to 2026-10-14 21:26:48. The redundant app.kite.revenge release package was not recreated.
9. Interactive device QA was deliberately not forced after installation. Secure keyguard was off, but the phone remained actively in unrelated UI (Instagram, Notification Shade, then Etar Calendar during the validation window). I did not steal focus merely to manufacture screenshot evidence. Therefore this checkpoint does not claim live reply/edit/attachment-menu geometry, keyboard-inset proof, dark-theme side-by-side parity or a new 120 Hz result.
10. Next substantial slice: when the Samsung is safely available, exercise reply/edit/attachment + keyboard/insets in Kite side-by-side against the read-only Messages reference and fix any measured mismatch immediately; then complete dark-theme/accessibility and remaining reaction/action-sheet consistency before a controlled large-history 120 Hz comparison against stock Revenge.

## Google Messages visual migration — system navigation and receipt cleanup, 2026-10-14

1. Fixed the open-chat system-navigation backdrop after the global transparent edge-to-edge change. ConversationScreen now paints its root with MaterialTheme.colorScheme.surface, so the transparent Android navigation area sees the same base surface as the inbox rather than the timeline's surfaceContainerLow treatment.
2. Read receipts are now rendered only on the latest own message in the current timeline. ConversationScreen derives one latest-own-message key from the already-rendered timeline list and passes a plain boolean through ConversationItemRow/EventRow; older messages no longer each show receipt avatars. No new Matrix collectors or per-row flows were added.
3. The multi-select action row now uses the same composerBottomPadding as the composer: navigation-bar inset + 12dp when the IME is closed, or 12dp above the IME when open. This prevents the selection controls from colliding with Samsung's system navigation area.
4. Validation: git diff --check PASS; :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop PASS; full :composeApp:desktopTest PASS. Final clean detached :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a PASS.
5. Installed the exact clean PerfDebug artifact over app.kite.revenge.debug only. APK size 107,853,016 bytes; SHA-256 e0806e173ae397959673f1b71a10a4f926ed6fdeff9d9ebacb4c52b517e13835; AAPT reports package app.kite.revenge.debug, label Kite, arm64-v8a.
6. Preserved the separate unfinished hide-room edits in InboxViewModel.kt, AppStateStore.kt, and strings.xml unstaged and outside these commits.


## Google Messages visual migration — seventeenth implementation session, 2026-10-14

1. Continued the conversation/action/settings pass from cfbe448d using the pinned docs/design-reference/google-messages/03-material3-settings.jpg and 06-dark-attachment-menu.webp references. The deliberate inbox bottom-search exception remains unchanged. The Samsung was connected but actively showing Gallery during this session, so I did not steal focus to open either Kite or Google Messages; no SMS/RCS state was touched.
2. Integrated the two immediately preceding conversation fixes already checkpointed locally: 3e4e01f6 gives the open-chat root an explicit Material surface through the navigation region and renders read receipts only beneath the latest own message; f4057eb8 lifts the multi-select action row by the same composer/system-navigation bottom padding so it no longer collides with Samsung navigation.
3. Consolidated the remaining conversation bottom sheets around one lightweight KiteModalBottomSheet: 32dp top corners, surfaceContainerLow, and common content color. Attachment actions now follow the Messages launcher order for Kite's supported actions (Gallery, Camera, File) and use darker tonal icon wells in dark mode. Message More is now a flat 56dp action list rather than nested cards/icon wells; Message Info and Report share the same sheet treatment, and Report uses a filled tonal rounded reason field plus explicit destructive action coloring. All edit/thread/pin/download/info/report/delete/attachment callbacks stay on their existing Matrix/Composer pathways.
4. Reduced the selected-message toolbar to evenly distributed 48dp icon buttons with accessibility content descriptions instead of a horizontally scrolling row of text buttons. Reply/retry/copy/forward/delete/more behavior is unchanged, destructive tint remains explicit, and no new state collectors or message-row allocations were introduced.
5. Replaced the legacy Material 2 ListItem used by shared settings preferences with a Material 3 Surface/Row implementation matching the pinned Messages settings hierarchy: 12dp rounded low-tonal rows, 64dp/76dp minimum heights depending on secondary content, 20dp horizontal content padding, bodyLarge/bodyMedium typography, neutral disabled alpha and 16dp trailing-control separation. Existing ScPref value/enabled state, keyboard focus/action providers, copy actions, switches and navigation behavior are preserved. The settings root now explicitly paints MaterialTheme.colorScheme.surface behind those rows/system edges.
6. Validation on Glass/JDK25: git diff --check PASS; :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop --no-daemon PASS; full :composeApp:desktopTest --no-daemon PASS (55 actionable tasks, BUILD SUCCESSFUL in 34s). One compile attempt hit the known generated KSP RevengeDatabase_Impl.kt disappearance race; clearing only composeApp/build/generated/ksp and rerunning recovered. Source implementation commit is b7fd251b.
7. Built the release-like device artifact from a fresh local clone at b7fd251b, with pinned matrix-rust-sdk revision 128049fd3b183f059fb76402c82ce56ba7ddcd37, so the unrelated local hide-room edits could not enter the APK. The first packaging pass hit the previously seen generated native-library strip race; clearing only the PerfDebug stripped_native_libs / merged_native_libs intermediates and rerunning completed packaging. Final APK is 107,853,016 bytes, SHA-256 1e752a246a8d5322a5f8d6ac80d1839ead6ad2cb48d1952b941c5e804b15e858; AAPT reports package app.kite.revenge.debug, label Kite, version perfdebug-26.10.14, target SDK 37, native-code arm64-v8a; apksigner verifies the existing Brandon Presley certificate SHA-256 011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd.
8. Device preflight on Samsung S25 serial <private-adb-device> confirmed app.kite.revenge.debug already existed and the redundant app.kite.revenge release package was absent. pm path app.kite returned no package on this device at this checkpoint, so no assumption or operation was made against a production Flutter package. Installed only the verified app.kite.revenge.debug artifact with adb install -r; install returned Success. The app was deliberately not launched because Gallery remained foreground.
9. Preserved the separate unfinished hide-room files byte-for-byte and unstaged: InboxViewModel.kt SHA-256 cdaf2fb2a102299080109a6e7175925aed348fa92a7c1edd7679d8f6367394d7, AppStateStore.kt 7571871842868354b4f23e8f63d6e2e8317d8eef461bc565e14660ecf3347673, and strings.xml dafd5af2280836f57325a5dc11b099be8045d0705001ef08839b5a59a1330b4a.
10. Device visual/performance QA remains intentionally unclaimed for this checkpoint: there is no fresh live screenshot of the new action sheets/settings, no keyboard/inset interaction proof after this artifact, and no controlled 120 Hz frame-time comparison. Next substantial slice should begin with unlocked/idle Samsung side-by-side QA of long-press selection, More/Info/Report, attachment sheet, settings and dark mode; fix observed mismatches in the same run, then collect controlled large-history 120 Hz evidence against the Revenge baseline.

## Google Messages visual migration — keyboard send and continuous chat backdrop, 2026-10-14

1. Removed the dedicated circular send button from the open-chat composer. The text field now advertises IME action Send and dispatches the existing ComposerViewModel.sendMessage path from the keyboard action only when the draft is sendable, no send is already in progress, and body validation passes. Sending progress and the existing nonstandard-mode clear control remain available when applicable.
2. Corrected the previous open-chat navigation-backdrop treatment: the ConversationScreen root now uses the same surfaceContainerLow as the visible timeline surface, so the area behind the floating composer and transparent Android system navigation is continuous with the conversation body instead of switching to a different base surface.
3. The first validation attempt in the active dirty worktree was blocked by an unrelated concurrent SettingsScreen import error. The exact implementation commit aff4a8aa was therefore validated in a clean detached worktree: Android compile PASS, desktop compile PASS, full :composeApp:desktopTest PASS. A transient matrix Android build-directory race on the first clean compile was cleared by rerunning serially with one Gradle worker; the serial clean validation passed.
4. Current main advanced with the adjacent keyboard-inset/action-sheet/search work to dbb9929d without changing ComposerRow or the chat backdrop fix. A clean arm64 :androidApp:assemblePerfDebug at dbb9929d PASS and was installed only over app.kite.revenge.debug. Final installed APK size 107,853,016 bytes; SHA-256 4c50cb523a6f8cb005993776036ebddbcd679501b56b4cb64f83dfda057de058; AAPT reports package app.kite.revenge.debug, label Kite, arm64-v8a.
5. The Samsung had NotificationShade in foreground during installation, so no forced live send was performed. The implementation is compiled/package-verified, but this checkpoint does not claim an actual Matrix message was transmitted from the IME during device QA.

### Seventeenth-session integrated-tip package follow-up

After the b7fd251b visual slice was committed, concurrent adjacent work advanced main through aff4a8aa, 0519b4ec and dbb9929d, with documentation tip be41bea7. To avoid leaving the handset on the intermediate b7fd251b artifact, exact be41bea7 was rebuilt from the same clean validation clone. The integrated :composeApp:desktopTest pass completed successfully, :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a completed successfully, and the final APK is 107,853,016 bytes with SHA-256 af7729ea7d35f948f84c79770cf130d60b8e3eec9949ef31bd07c9be2cb4dc6c. AAPT reports app.kite.revenge.debug, Kite, target SDK 37 and arm64-v8a. That exact integrated artifact was installed with adb install -r over app.kite.revenge.debug only. Kite was not launched because Gallery remained foreground, so the device-visual and 120 Hz limitations above still apply.


## Google Messages visual migration — eighteenth implementation session, 2026-10-14

1. Continued the open-conversation visual pass from the integrated 527787d3 checkpoint. The pinned Google Messages reference set remained the stable baseline. The connected Samsung S25 was securely locked when device reference gathering began, so no attempt was made to bypass the lock or mutate SMS/RCS state. Current public September 2026 Google Messages reference material was used only to resolve the in-chat search direction: Messages is moving toward a dedicated in-chat search mode with its editable search control at the bottom rather than squeezing the query field into the conversation app bar.
2. Reworked message multi-select into a Google-Messages-style contextual top app bar. The previous rounded bottom selection dock is gone; Close, selected-count, Reply/Retry, Copy, Forward, More and multi-delete now live in the top navigation as icon actions. All callbacks still route through the existing ConversationViewModel / event action provider / MessageForward / redaction paths, so no parallel Matrix action state was introduced.
3. Reworked open-chat search around the same dedicated-mode structure. Search mode now keeps a simple Back + Search header while the existing SearchBar/query provider renders as a rounded bottom control with the same IME/navigation inset treatment as the composer. ConversationScreen collects the search-mode flow once and passes a plain flag into ConversationTopNavigation, removing the previous duplicate search visibility collector from the header.
4. Removed the composer's slide/expand + shrink exit animation. The old visibility animation changed the bottom layout height during mode/close transitions, forcing the timeline to remeasure at the end and matching the reported end-of-close jolt. The composer is now composed directly when visible, while search and selection replace it without a height-changing exit animation. Composer autofocus is also suppressed while in-chat search owns input focus.
5. Source validation on Glass/JDK25 for the exact implementation: git diff --check PASS; :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop --no-daemon --max-workers=1 PASS (BUILD SUCCESSFUL in 37s); full :composeApp:desktopTest --no-daemon --max-workers=1 PASS (55 actionable tasks, BUILD SUCCESSFUL in 7s). The cohesive source checkpoint is commit d0831f9c (Move chat search and selection actions into Messages-style surfaces), changing only ConversationScreen.kt, ConversationTopNavigation.kt and MessageSelectionBar.kt (217 insertions / 238 deletions).
6. Built the device artifact from a fresh clean local clone pinned exactly to d0831f9c with matrix-rust-sdk revision 128049fd3b183f059fb76402c82ce56ba7ddcd37, so the unrelated unfinished hide-room files could not enter the APK. Packaging encountered generated-output races rather than source failures: first the PerfDebug native-library merge blame output disappeared, then a generated res-jvm.jar was truncated. Clearing only those generated intermediates and rerunning serially completed :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon --max-workers=1 successfully (275 actionable tasks, BUILD SUCCESSFUL in 1m05s).
7. Final clean APK: /home/brandon/worktrees/kite-revenge-validate-d0831f9c/androidApp/build/outputs/apk/PerfDebug/androidApp-PerfDebug.apk, 107,853,016 bytes, SHA-256 fbfd1ddfe5e782ee529f590caaea88c41d19f61c8c2b667c95f7ce3282f7bd56. AAPT reports package app.kite.revenge.debug, label Kite, version perfdebug-26.10.14, target SDK 37 and native-code arm64-v8a. apksigner verifies the existing Brandon Presley V2 certificate SHA-256 011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd.
8. Device safety/install proof on Samsung S25 serial <private-adb-device>: before installation app.kite.revenge.debug existed while app.kite.revenge and app.kite did not resolve via pm path. adb install -r of the exact APK returned Success. After installation only app.kite.revenge.debug was present among those native/production package IDs; its data directory remained /data/user/0/app.kite.revenge.debug, firstInstallTime remained 2026-10-14 11:55:12, and lastUpdateTime advanced to 2026-10-14 22:24:56.
9. The Samsung remained securely locked, so this checkpoint deliberately does not claim screenshot proof of the new contextual selection bar, bottom in-chat search, close-jolt fix, keyboard geometry, dark-theme parity or 120 Hz frame timing. No Kite room was opened, no SMS/RCS conversation was opened, and no message/search action was executed merely to manufacture evidence.
10. The separate unfinished hide-room edits in InboxViewModel.kt, AppStateStore.kt and strings.xml were left unstaged and untouched by this implementation commit. Next substantial slice: when the Samsung is normally unlocked/idle, do side-by-side visual QA of the contextual selection app bar, bottom in-chat search, close transition, composer/reply/edit/attachment + IME behavior and dark mode; fix measured mismatches immediately, then collect controlled large-history 120 Hz frame evidence against the Revenge baseline.

## Google Messages visual migration — nineteenth implementation session, 2026-10-14

1. Continued from the integrated Messages-style conversation/search/selection work using the pinned docs/design-reference/google-messages/01-official-conversation.png and 05-material3-chat.webp conversation references. Both reinforce a clean bubble-first timeline and low-noise conversation chrome. The Samsung was reachable but remained in Doze for this slice, so I did not wake it solely to inspect Google Messages or Kite and did not mutate any SMS/RCS state. The deliberate Inbox bottom-search exception remains unchanged.
2. Completed the verification/security-chrome cleanup in commit b5e117f6 (Remove Matrix warning chrome and membership noise). MessageBubble no longer carries or renders passive MessageShield authenticity/unverified/unsigned/unknown-device decorations; routine timestamp metadata is now only driven by edited/sending/send-failure state. Actual send failures remain visible. The dead TimestampSettings object plus its bridge/authenticity preference combine flow were removed from ConversationViewModel, along with the now-unused pass-through across ConversationScreen, ConversationItemRow and EventRow.
3. Finished the corresponding Matrix/server-event cleanup instead of merely hiding controls after loading them. Public-room membership events are now disabled in both the live RustRoomFactory timeline filter and focused/threaded JoinedRustRoom filter, while the existing Kite row-level guard continues to suppress membership/profile/state/unknown event rows that make it through other contexts. The obsolete “message authenticity warnings” settings category and “membership events in public rooms” toggle were removed, so Settings no longer exposes controls for UI Kite intentionally does not render.
4. This cleanup reduces hot-path work rather than adding it: the per-conversation authenticity/bridge flow and its state collection are gone, and public membership noise is rejected at Matrix timeline configuration rather than loaded for a presentation layer that will discard it. No new per-row collector, animation, duplicated Matrix state or blocking UI work was introduced.
5. Added native Android notification actions in commit 201e8a1f (Add native notification reply actions). Message-like notifications can now expose Android RemoteInput Reply plus Mark as read, and likely OTP/code messages can expose Copy code. Reply restores the existing Matrix session, obtains the joined room and sends through its existing live Matrix Rust timeline, so encrypted rooms retain the normal SDK encryption/send path rather than creating a parallel client stack. Mark-read sends private-read plus fully-read markers and then dismisses the room notification. The explicit action receiver is android:exported=false and runs the Matrix work from goAsync() on the existing global coroutine scope.
6. Kept Copy code deliberately conservative. NotificationCodeExtractor accepts a standalone 4–8 digit token when the text contains an explicit code/OTP/verification/PIN/two-factor hint, otherwise only a numeric-only six-digit message. Focused tests cover explicit codes, numeric-only six-digit input, ordinary address/order numbers and longer embedded numbers.
7. Fixed adjacent notification-history bookkeeping while touching that path. The old code captured previousMessageCount after appending the new event, so media-with-caption events that render as more than one MessagingStyle.Message could leave the parallel event-ID list misaligned. Existing history is now validated before reuse, malformed/misaligned history is discarded safely, the pre-append message count is captured correctly, and one Matrix event ID is appended for every rendered notification message. This keeps later notification redaction/history lookup aligned.
8. Source validation on Glass/JDK25: git diff --check PASS; focused :composeApp:desktopTest --tests chat.schildi.revenge.notification.NotificationCodeExtractorTest --no-daemon --max-workers=1 PASS; :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop --no-daemon --max-workers=1 PASS; full :composeApp:desktopTest --no-daemon --max-workers=1 --console=plain PASS (55 actionable tasks, BUILD SUCCESSFUL in 27s).
9. Release-like packaging was isolated from the three unrelated local hide-room edits using fresh clone /home/brandon/worktrees/kite-revenge-validate-201e8a1f at exact source commit 201e8a1f48f8bd31c3e838f900955d764cf86cd0 and pinned matrix-rust-sdk revision 128049fd3b183f059fb76402c82ce56ba7ddcd37. Final :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon --max-workers=1 PASS (275 tasks on the cached verification rerun). APK androidApp/build/outputs/apk/PerfDebug/androidApp-PerfDebug.apk is 107,853,468 bytes, SHA-256 ac3c7c37a7f4267f3eac4d2c30acfdc1c146a92bca6e4e90791e2813c7bcee83; apkanalyzer reports application ID app.kite.revenge.debug. The merged manifest confirms NotificationActionReceiver is non-exported.
10. Device safety/install proof on Samsung S25 serial <private-adb-device>: preflight found app.kite.revenge.debug installed and app.kite.revenge absent; the exact verified PerfDebug APK was installed with adb install -r, which returned Success. Android reports version perfdebug-26.10.14 and lastUpdateTime=2026-10-14 23:15:00. The phone remained mWakefulness=Dozing after installation and Kite was not launched.
11. Live notification-action and visual/performance QA are deliberately not claimed. No real Matrix notification was generated just to exercise Reply/Mark read/Copy code, no SMS/RCS conversation was opened for reference gathering, and the dozing handset was not awakened for screenshots. There is therefore no fresh on-device action-button layout proof, composer/IME/dark-mode comparison, or new 120 Hz frame-time result in this checkpoint.
12. The unrelated unfinished hide-room files remain unstaged and byte-for-byte at their pre-run hashes: InboxViewModel.kt cdaf2fb2a102299080109a6e7175925aed348fa92a7c1edd7679d8f6367394d7, AppStateStore.kt 7571871842868354b4f23e8f63d6e2e8317d8eef461bc565e14660ecf3347673, and common strings.xml dafd5af2280836f57325a5dc11b099be8045d0705001ef08839b5a59a1330b4a.
13. Next substantial slice: when the Samsung is normally unlocked/idle, exercise a real incoming debug-profile notification (without touching production state) to verify Reply/Mark read/Copy code presentation and behavior, then run side-by-side Kite/Google Messages QA across contextual selection, bottom in-chat search, reply/edit/attachment + IME/insets and dark mode. Fix visible mismatches in the same run, then collect a controlled large-history 120 Hz comparison against the stock Revenge baseline.

## Google Messages visual migration — twentieth implementation session, 2026-10-14

1. Continued from the nineteenth-session conversation cleanup using the pinned `docs/design-reference/google-messages/01-official-conversation.png` and `05-material3-chat.webp` references, with the committed reference README as the stable mapping. A fresh public September/August 2026 Google Messages cross-check still shows the Material 3 conversation/details hierarchy and the newer compact message-action presentation. The Samsung S25 remained securely locked and asleep for device validation, so I did not wake it solely to inspect Messages/Kite or mutate any SMS/RCS state. The deliberate Inbox bottom-search exception remains unchanged.
2. Completed a coherent transient-loading cleanup in `ae6de665` (`Polish conversation loading and profile surfaces`). Added one shared 350ms transient-loading grace helper and reused it for splash/navigation and conversation paging. Fast pagination now stays visually silent while the row keeps a stable 32dp slot; genuinely slow paging gets a compact 20dp indicator without a late timeline remeasure. Pending replied-to content now uses a quiet fixed-size tonal skeleton instead of flashing a spinner, and avatar loading keeps the same neutral fallback rather than changing color while the network image resolves. Splash failures still force immediate progress/error visibility.
3. Tightened open-chat navigation/search without adding Matrix state. The avatar and room/contact title are now one continuous participant hit target with a 36dp circular avatar and single-line `titleMedium` hierarchy, still routing direct chats to the existing user-details destination and group rooms to room details. Shared search now has an explicit Search IME action plus a 56dp minimum top-navigation treatment; it continues to use the existing search provider/handler path.
4. Simplified the adjacent details/profile surface to match the cleaner Messages identity hierarchy rather than Revenge's diagnostic presentation. User details now show one centered 104dp circular primary avatar and one centered primary display name instead of duplicate room/global avatar and `room name / global name` pairs. The profile-level verification badge/state collector was removed from this normal contact surface; Matrix user ID and mutual-room functionality remain. Room details now uses the same 104dp circular avatar treatment. This also removes a duplicate avatar request and one `userIdentity` collection rather than adding hot-path state.
5. Performance ownership remains bounded: no new Matrix flow/collector, no per-message collector, no blur/effect pass and no duplicated room state were introduced. The transient helper exists only while its loading composable exists and delays paint rather than delaying data. The participant header passes existing plain values/callbacks. No claim of 120Hz parity is made without a controlled device measurement.
6. Exact source validation on Glass/JDK25 for `ae6de665`: `git diff --check` PASS; `:composeApp:compileAndroidMain :composeApp:compileKotlinDesktop :composeApp:desktopTest --no-daemon --max-workers=1` PASS (87 tasks, BUILD SUCCESSFUL). The source checkpoint was pushed to private-fork `main`.
7. Release-like validation was isolated from all local unfinished work in a clean clone at exact superproject `ae6de6651c980d7683392eccb5dabb2e893f9014` with `matrix-rust-sdk` pinned to `128049fd3b183f059fb76402c82ce56ba7ddcd37`. `:androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon --max-workers=1` completed successfully (275 tasks, BUILD SUCCESSFUL). Final APK is 107,853,468 bytes with SHA-256 `961c19ca543e881b7381a49c95cb5702523b1fe4605d64c43ff63806e219f83d`. `aapt2` reports package `app.kite.revenge.debug`, label `Kite`, version `perfdebug-26.10.14`, target SDK 37 and native code `arm64-v8a`; `apksigner` verifies the existing V2 certificate SHA-256 `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd`.
8. Device safety/install proof: before and after installation, `app.kite` and redundant `app.kite.revenge` did not resolve via `pm path`; only `app.kite.revenge.debug` was targeted. The exact verified APK was installed with `adb install -r`, preserving `dataDir=/data/user/0/app.kite.revenge.debug` and `firstInstallTime=2026-10-14 11:55:12`; `lastUpdateTime` advanced to `2026-10-14 23:51:10`. The phone remained under secure keyguard with `INTERACTIVE_STATE_SLEEP`; Kite was not launched and no Messages conversation was opened.
9. Preserved the original unfinished hide-room edits byte-for-byte: `InboxViewModel.kt` SHA-256 `cdaf2fb2a102299080109a6e7175925aed348fa92a7c1edd7679d8f6367394d7`, `AppStateStore.kt` `7571871842868354b4f23e8f63d6e2e8317d8eef461bc565e14660ecf3347673`, and `strings.xml` `dafd5af2280836f57325a5dc11b099be8045d0705001ef08839b5a59a1330b4a`. A separate concurrent slice also dirtied `ComposerRow.kt` and `SearchBar.kt` after `ae6de665`; those post-checkpoint edits were deliberately left untouched and outside this session's commits.
10. Device visual/performance QA remains intentionally unclaimed for this checkpoint: there is no fresh unlocked screenshot proof of the participant header, details/profile page, paging/skeleton loading, search IME geometry or dark mode, and no new 120Hz frame-time comparison. Next substantial slice should begin on an unlocked/idle Samsung with side-by-side header/profile/loading/search QA against the read-only Messages reference, fix measured mismatches in the same run, then finish dark-theme/accessibility/detail/action-surface consistency and collect a controlled large-history 120Hz comparison against the Revenge baseline.


## 2026-10-15 — Messages-style search, composer, actions, and receipts

### Visual reference
- Re-read the pinned Google Messages baseline in `docs/design-reference/google-messages/README.md`, especially the conversation/composer and dark attachment references.
- Cross-checked the current stable Google Messages long-press redesign (floating action menu with reactions kept above it) and the current/rolling read-receipt treatment. The Samsung reference device remained `Dozing`, so this slice deliberately did not wake or mutate Google Messages for reference capture.
- Kept the intentional Kite exception: inbox search remains at the bottom.

### Implemented
- Replaced the stock Material `TextField` rendering used by the Messages-style search path with a lightweight `Surface + BasicTextField` capsule:
  - fixed 56dp minimum height and 28dp radius,
  - explicit search/clear icon sizing and padding,
  - Material surface/on-surface roles,
  - search IME action and existing `FocusRole.SEARCH_BAR` behavior preserved.
  - Generic/non-Messages search keeps the existing stock `TextField` path.
- Tightened the conversation composer:
  - gallery shortcut now disappears when the field gains focus or contains text, matching the Google Messages text-field behavior,
  - removed `AnimatedVisibility`/`AnimatedContent`/`animateColorAsState` from the frequently changing composer affordances,
  - send progress now lives inside the composer capsule and uses the existing 350ms transient-loading grace period, avoiding a separate flashing spinner/layout slot for quick sends,
  - the explicit send button remains absent; IME Send continues to submit.
- Updated long-press message actions:
  - retained Kite/Matrix-specific edit, pin, reactions, and other capabilities,
  - moved media download/save after Info so the primary action ordering follows the current Google Messages floating menu more closely,
  - removed an unnecessary menu-container color animation.
- Compacted the already-last-own-message-only read receipt row:
  - align receipts to the outgoing/right edge,
  - show at most three overlapping receipt avatars plus `+N`,
  - preserve the full Matrix receipt set in the existing tap popup.

### Validation
- `git diff --check`: pass.
- `:composeApp:compileAndroidMain :composeApp:compileKotlinDesktop`: pass.
- `:composeApp:desktopTest`: pass.
- Clean detached exact-commit validation worktree at `8c6bf390`, Matrix Rust SDK pinned to `128049fd3b183f059fb76402c82ce56ba7ddcd37`.
- `:androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a`: pass after clearing only raced generated `merged_native_libs/PerfDebug` / `stripped_native_libs/PerfDebug` intermediates. Final retry: `BUILD SUCCESSFUL in 1m 41s`.
- Built output metadata verified `applicationId=app.kite.revenge.debug`, variant `PerfDebug`, `versionName=perfdebug-26.10.14`.
- Installed with `adb install -r` on Samsung `<private-adb-device>`; package data/login preserved. Device remained dozing and the app was not launched or force-stopped.
- Post-install package evidence: `app.kite.revenge.debug`, versionCode 1, versionName `perfdebug-26.10.14`, lastUpdateTime `2026-10-15 00:13:02`.
- The pre-existing hide-room work remains unstaged and byte-for-byte unchanged:
  - `InboxViewModel.kt` SHA-256 `cdaf2fb2a102299080109a6e7175925aed348fa92a7c1edd7679d8f6367394d7`
  - `AppStateStore.kt` SHA-256 `7571871842868354b4f23e8f63d6e2e8317d8eef461bc565e14660ecf3347673`
  - `strings.xml` SHA-256 `dafd5af2280836f57325a5dc11b099be8045d0705001ef08839b5a59a1330b4a`

### Next substantial slice
- When the Samsung is naturally awake/unlocked, do side-by-side screenshot QA of the new bottom in-chat search, composer focus/typing states, long-press floating menu, and compact receipt treatment against installed Google Messages.
- Continue with precise partial-text copy inside the long-press flow and the current Google Messages swipe model (right-to-reply / left-to-reveal timestamps) only after confirming those gestures do not conflict with Kite's existing Matrix quick-reply semantics and 120Hz performance target.

## 2026-10-15 00:42 NZDT — Google Messages swipe/timestamp reveal + partial-copy plumbing

### Visual / interaction reference
- Re-read the pinned Google Messages reference README before changing the conversation interaction surface.
- Cross-checked the current stable Google Messages behavior: right-swipe on a message replies; left-swipe reveals per-message timestamps across the visible conversation; the current long-press flow supports selecting part of message text after entering message actions.
- The Samsung remained Dozing throughout final validation, so Google Messages and Kite were not launched or mutated for visual reference capture in this slice. No side-by-side screenshot claim is made.

### Implemented
- Moved the default touch swipe mapping to the current Google Messages model while preserving Kite's configurable Matrix actions:
  - left swipe = timestamp reveal,
  - right swipe = reply,
  - explicit non-default swipe pairs remain unchanged,
  - the historical touch default pair left=REPLY/right=NONE resolves at runtime to the new mapping so existing installs get the current gesture without rewriting preferences.
- Added one stable conversation-level MessageTimestampRevealState instead of adding per-row collectors/state duplication. A left timestamp drag updates one float; visible message rows shift through layout/layer state reads while each row fades its already-available timestamp into the trailing edge.
- Kept right-swipe reply on the existing Matrix compose-reply action path. Existing reaction/edit/read-marker swipe actions remain available through preferences.
- Shifted the message content plus its reactions/thread/read-receipt metadata together during timestamp reveal so the interaction reads as one conversation surface rather than moving only a bubble.
- Added touch partial-selection plumbing to the existing formatted-message renderer: message text remains non-selectable during normal scrolling, then enables the existing Compose SelectionContainer while the message action surface is open.
- Added pure desktop tests covering legacy-default migration, current default stability, and preservation of explicit custom swipe pairs.
- Reused the existing localized message_info_time resource for the new preference entry; the unrelated dirty resource file was not edited by this slice.

### Validation
- Main worktree source checkpoint: 44a08be32de1126683688dfca7cd10549987111d (Match Messages swipe and text selection interactions).
- git diff --check: pass before checkpoint.
- :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop :composeApp:desktopTest --no-daemon --max-workers=1: pass (91 actionable tasks, BUILD SUCCESSFUL).
- Focused MessageSwipeActionsTest plus Android/desktop compile also passed before the full suite.
- Release-like packaging isolated from the three unrelated hide-room edits using fresh clone /home/brandon/worktrees/kite-revenge-validate-44a08be3, exact superproject commit 44a08be3, Matrix Rust SDK 128049fd3b183f059fb76402c82ce56ba7ddcd37.
- :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon --max-workers=1: pass (275 actionable tasks, BUILD SUCCESSFUL in 5m03s). The orchestration timeout replayed the same Gradle command once; the newer duplicate was terminated immediately so generated outputs had a single writer.
- Final clean APK: androidApp/build/outputs/apk/PerfDebug/androidApp-PerfDebug.apk, 107,853,468 bytes, SHA-256 718493ac85b91d4451fdf660b01851cffa2a85e77586e8b10e3e38eef412de82.
- AAPT: package app.kite.revenge.debug, label Kite, version perfdebug-26.10.14, target SDK 37, native-code arm64-v8a.
- APK signature verified with existing V2 signer SHA-256 011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd.
- Samsung <private-adb-device> preflight found only app.kite.revenge.debug among the native migration packages; installed the exact verified APK with adb install -r and received Success.
- Existing debug app data was preserved: firstInstallTime=2026-10-14 11:55:12, dataDir=/data/user/0/app.kite.revenge.debug; post-install lastUpdateTime=2026-10-15 00:41:33.
- Device remained mWakefulness=Dozing / non-interactive after installation. Kite was not launched and the phone was not woken merely for QA.
- No 120 Hz frame-time or visual-parity claim is made for the new swipe. Static hot-path review confirms this slice adds no Matrix collectors and uses one shared primitive Compose state, but device measurement is still required.
- The pre-existing hide-room work remains unstaged and byte-for-byte unchanged:
  - InboxViewModel.kt SHA-256 cdaf2fb2a102299080109a6e7175925aed348fa92a7c1edd7679d8f6367394d7
  - AppStateStore.kt SHA-256 7571871842868354b4f23e8f63d6e2e8317d8eef461bc565e14660ecf3347673
  - strings.xml SHA-256 dafd5af2280836f57325a5dc11b099be8045d0705001ef08839b5a59a1330b4a

### Concrete remaining QA / next substantial slice
- When the Samsung is naturally awake/unlocked, verify the installed build side-by-side with installed Google Messages:
  - right swipe replies without accidental vertical-scroll capture,
  - left swipe reveals aligned timestamps across a long visible history and springs back cleanly,
  - long-press then second-long-press on text produces partial-selection handles; Compose popup focus/outside-touch behavior is the known interaction risk and must not be claimed solved until this is observed,
  - attachment/reaction/read-receipt rows move coherently with the timestamp reveal,
  - dark theme and keyboard/inset behavior remain stable.
- Capture gfxinfo/frame evidence during repeated swipes on a long room at 120 Hz. If the shared reveal still causes avoidable layout work, move more of the translation to graphics-layer-only placement before continuing.
- After that QA, continue the next nearby Google-Messages-style conversation slice rather than adding another parallel state system.

## 2026-10-15 01:20 NZDT — In-place mobile conversation navigation + selection/loading polish

### Visual / interaction reference
- Re-read the pinned Google Messages baseline in docs/design-reference/google-messages/README.md before changing the conversation surface.
- Kept the intentional Kite exception unchanged: inbox search remains at the bottom.
- The Samsung stayed Dozing / non-interactive for this checkpoint, so neither Google Messages nor Kite was woken merely for screenshot QA. No fresh visual-parity or 120 Hz frame-time claim is made.

### Implemented
- Removed the normal Android Inbox -> Conversation Activity hop that was a concrete source of the reported open/close end-jolt:
  - NavigationPreference.AUTO now keeps the mobile Inbox -> Conversation pair in the current Activity only when platformWindowManager.appOwnsWindows == false.
  - Desktop category/window behavior is unchanged, and explicit new-window/new-task navigation remains available.
  - The compact conversation toolbar Back button now replaces the conversation with Inbox on Android instead of closing the Activity.
  - Android system Back does the same while a conversation is active; non-conversation back behavior still follows the existing Activity finish/remove-task path.
- Added DestinationNavigationPolicyTest coverage proving mobile Inbox -> Conversation stays in-place, desktop preserves separate-window behavior, and same-category navigation remains in-place.
- Reduced single-message selection-bar crowding:
  - single selection now keeps Reply/Retry, Copy, and More as the primary compact actions,
  - Forward remains available in the existing Messages-style More sheet,
  - multi-select keeps the bulk Forward action in the top bar.
- Increased the existing transient-loading grace period from 350 ms to 650 ms so short timeline/send transitions are less likely to paint a one-frame circular spinner; failure states still force the loading/error surface immediately.
- No new Matrix collectors or parallel timeline state systems were added.
- Investigated partial-text selection and confirmed the current plumbing is structurally unreliable because touch selection is tied to the open custom popup while the platform text context menu is suppressed. An explicit-selection-mode experiment was discarded cleanly after edit-tool blocking; partial text selection is therefore not claimed fixed in this checkpoint.

### Validation
- Source checkpoint: 1cac98ed74eb2cb1e921a84b16b6953837e4c3a9 (Smooth mobile conversation navigation and selection).
- git diff --check: pass before checkpoint.
- :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop --no-daemon --max-workers=1: pass with JDK 25.
- Focused DestinationNavigationPolicyTest + SplashScreenContentTest: pass.
- Full :composeApp:desktopTest --no-daemon --max-workers=1 --console=plain: pass (BUILD SUCCESSFUL).
- Release-like validation used isolated clean clone /home/brandon/worktrees/kite-revenge-validate-1cac98ed at exact superproject 1cac98ed74eb2cb1e921a84b16b6953837e4c3a9 and Matrix Rust SDK 128049fd3b183f059fb76402c82ce56ba7ddcd37.
- :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon --max-workers=1 --console=plain: pass (BUILD SUCCESSFUL in 4m 52s). A timeout replay briefly created a duplicate Gradle writer; the duplicate was stopped before packaging and the original single writer completed successfully.
- Final APK: androidApp/build/outputs/apk/PerfDebug/androidApp-PerfDebug.apk, 107,853,468 bytes, SHA-256 654eecf32a49dc35a2761a1996614013a0456a69d5c9880cd59336fe57dd5ebb.
- AAPT: package app.kite.revenge.debug, label Kite, version perfdebug-26.10.14, target SDK 37, native code arm64-v8a.
- APK signature verified with existing V2 signer SHA-256 011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd.
- Samsung preflight found neither app.kite nor redundant app.kite.revenge; only app.kite.revenge.debug was present and targeted. Installed the exact verified APK with adb install -r.
- Debug app state was preserved: dataDir=/data/user/0/app.kite.revenge.debug, firstInstallTime=2026-10-14 11:55:12, lastUpdateTime=2026-10-15 01:20:16.
- Device remained mWakefulness=Dozing and mHalInteractiveModeEnabled=false after installation; the app was not launched.
- The unrelated hide-room work remains unstaged and byte-for-byte unchanged:
  - InboxViewModel.kt SHA-256 cdaf2fb2a102299080109a6e7175925aed348fa92a7c1edd7679d8f6367394d7
  - AppStateStore.kt SHA-256 7571871842868354b4f23e8f63d6e2e8317d8eef461bc565e14660ecf3347673
  - strings.xml SHA-256 dafd5af2280836f57325a5dc11b099be8045d0705001ef08839b5a59a1330b4a

### Next substantial slice
- On a naturally awake/unlocked Samsung, compare the installed Kite build side-by-side with installed Google Messages and verify repeated Inbox <-> Conversation navigation has no end-jolt, the single-selection header/overflow density matches the reference better, and short loads no longer flash a spinner.
- Re-test the already-installed Messages-style right-swipe reply / left-swipe timestamp reveal on long histories, attachment/reaction/read-receipt rows, dark theme, keyboard/insets, and capture controlled gfxinfo/frame evidence at 120 Hz.
- Finish partial-text selection as an explicit message-scoped mode only after observing the actual native handle/context-menu interaction on device; do not reintroduce per-row Matrix collectors or broad timeline state.


## 2026-10-15 01:50 NZDT — Messages long-press/partial-copy interaction + menu hot-path cleanup

### Visual / interaction reference
- Re-read the pinned Google Messages reference mapping before changing the message-action surface.
- Cross-checked the now-wide stable Google Messages long-press redesign: reactions remain above a floating action list, the primary list includes Reply / Forward / Copy / Star / Delete / Select more / Info (plus Save for media), and precise partial copy is entered by long-pressing the selected message text a second time.
- Kept Kite's Matrix room Pin in the primary action stack as the closest existing Matrix-specific analogue to the reference's Star position; no Matrix capability was removed.
- The Samsung remained Dozing / non-interactive throughout implementation and installation, so neither Kite nor Google Messages was opened merely to manufacture screenshot evidence.

### Implemented
- Finished the partial-text-selection plumbing instead of adding a separate explicit selection mode:
  - Android message action popups are now non-focusable so a second long-press outside the popup can reach the selected message text.
  - Desktop message popups deliberately remain focusable, preserving keyboard/pointer menu navigation.
  - While a message action popup is open, the row-level click/long-click recognizer, swipe recognizer and passive double-tap-reaction recognizer stand down. This gives Compose text selection and its handle drags ownership of the touch stream; all normal first-long-press, swipe and double-tap behavior returns when the popup closes.
  - Normal touch scrolling still keeps message text non-selectable until its own action surface is open.
- Updated the message action wording from generic Select to the current Messages-style Select more without editing the unrelated dirty common strings.xml; the label lives in a dedicated Kite conversation resource file.
- Tightened the context-menu hot path for long histories:
  - the existing global open-menu state collector is retained, but consumption now goes through derivedStateOf, so rows whose own menu state stays Closed do not need composition invalidation merely because another row opens/closes a menu;
  - per-row window bounds from onGloballyPositioned are no longer stored in Compose snapshot state. Scrolling still updates the latest anchor geometry, but does not write a snapshot value on every row movement just to position a closed menu.
- No new Matrix collector, duplicated timeline state, animation/effect pass or blocking UI work was introduced.

### Validation
- Cohesive source checkpoint: 87de6793 (Polish Messages actions and gesture arbitration), 7 files, 61 insertions / 11 deletions.
- git diff --check: pass.
- Glass/JDK25 :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop :composeApp:desktopTest --no-daemon --max-workers=1 --console=plain: pass (BUILD SUCCESSFUL in 35s, 87 actionable tasks).
- Release-like validation used isolated detached worktree /home/brandon/worktrees/kite-revenge-validate-87de6793 at exact superproject 87de6793, with Matrix Rust SDK pinned to 128049fd3b183f059fb76402c82ce56ba7ddcd37.
- The initial clean :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon --max-workers=1 exceeded the connector's foreground call window but continued as the original single build; one replayed duplicate writer was terminated immediately. The original produced a fresh APK. A cached exact-command verification rerun then reported BUILD SUCCESSFUL in 3s, 275 actionable tasks (10 executed / 265 up-to-date).
- Final APK: /home/brandon/worktrees/kite-revenge-validate-87de6793/androidApp/build/outputs/apk/PerfDebug/androidApp-PerfDebug.apk, 107,853,803 bytes, SHA-256 8d28c03ed8369093343763659db3adcab7a46310a06e6b5ae1393a19c68f4c00.
- AAPT verifies package app.kite.revenge.debug, label Kite, version perfdebug-26.10.14, target SDK 37 and arm64-v8a. apksigner verifies the existing V2 signer SHA-256 011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd.
- Samsung <private-adb-device> preflight and postflight found neither production app.kite nor redundant app.kite.revenge; only app.kite.revenge.debug was targeted. adb install -r returned Success.
- Debug data/login was preserved: dataDir=/data/user/0/app.kite.revenge.debug, firstInstallTime=2026-10-14 11:55:12, lastUpdateTime=2026-10-15 01:49:34.
- Device remained mWakefulness=Dozing and mHalInteractiveModeEnabled=false; Kite was not launched. Precise-selection handles, popup dismissal, dark-mode appearance and 120 Hz frame timing therefore remain deliberately unclaimed.
- The pre-existing hide-room work remains unstaged and byte-for-byte unchanged:
  - InboxViewModel.kt SHA-256 cdaf2fb2a102299080109a6e7175925aed348fa92a7c1edd7679d8f6367394d7
  - AppStateStore.kt SHA-256 7571871842868354b4f23e8f63d6e2e8317d8eef461bc565e14660ecf3347673
  - strings.xml SHA-256 dafd5af2280836f57325a5dc11b099be8045d0705001ef08839b5a59a1330b4a

### Next substantial slice
- On a naturally awake/unlocked Samsung, test the exact Google Messages gesture sequence side-by-side: first long-press -> floating actions -> second long-press directly on text -> drag selection handles -> Copy/Select All surface. Verify popup touch-through/dismissal does not regress normal action taps.
- Re-run right-swipe reply / left-swipe timestamp reveal and double-tap reaction immediately after closing the menu to prove gesture arbitration restores cleanly.
- Capture controlled gfxinfo/frame evidence on a long room at 120 Hz, especially while scrolling rows that host closed context-menu anchors; only then claim a measurable hot-path improvement.
- Continue into the adjacent reactions/action-sheet/dark-theme polish from that observed device state rather than adding a parallel interaction/state system.

## 2026-10-15 02:26 NZDT — Messages conversation chrome, stable composer states, and transient-loading cleanup

### Visual / interaction reference
- Re-read the pinned Google Messages baseline in docs/design-reference/google-messages/README.md, including the official conversation/composer, Material 3 chat, inbox hierarchy, and dark attachment references.
- Preserved the intentional Kite exception: inbox search remains at the bottom.
- The Samsung stayed Dozing / non-interactive throughout device validation, so neither Google Messages nor Kite was launched merely for screenshot gathering. No fresh side-by-side visual-parity or 120 Hz frame-time claim is made in this slice.

### Implemented
- Removed Revenge's global frame-drop diagnostic spinner from WindowContent. Kite now relies on Android frame tooling for performance measurement instead of painting debug progress chrome over ordinary navigation.
- Reworked transient loading presentation so fast loads remain visually silent and sustained navigation/pagination uses a compact linear progress treatment instead of circular spinners:
  - SplashScreenContent still delays transient loading chrome and still surfaces failure details immediately.
  - Conversation pagination retains a fixed 32 dp slot to avoid timeline remeasure/jump, but uses a 56 x 2 dp progress line after the grace period.
  - Composer send-in-progress retains its trailing interactive-size slot without rendering a faux send-button/spinner; Matrix local echo remains the message-level send feedback and keyboard IME Send remains the send action.
- Removed app-bar crossfades for inbox/close icon changes, title changes, and generic search/title changes. These are now direct state swaps, reducing animated intermediate frames and late-title/search visual churn.
- Stabilized compact conversation header geometry:
  - Always render the existing 36 dp avatar component so rooms without an avatar URL get its generated fallback instead of shifting the title left.
  - Keep the conversation title in the top bar while bottom in-chat search is active instead of replacing it with a generic Search label.
  - Existing direct-message header tap still routes through the participant UserDetails destination.
- Tightened composer fallback states around the existing Messages-style 28 dp pill:
  - Normal composer and no-send-permission state now share the same rounded shape.
  - The no-send-permission surface receives the same caller bottom inset as the normal composer and uses the same horizontal dock margins instead of becoming a full-width rectangular Revenge bar.
  - Body-validation errors now use compact body-small text aligned to the composer content rather than appearing flush against the window edge.
- No Matrix collectors, duplicate timeline state, new animation systems, blocking UI work, or Flutter code were added.

### Validation
- Source checkpoint: 4dfda8a3ce28b92220d79ed6bc5a76ec5c84ffa0 (Polish Messages conversation chrome and loading), 6 source files, 110 insertions / 108 deletions.
- git diff --check: pass.
- Glass with JDK 25 + Android SDK: :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop :composeApp:desktopTest --no-daemon --max-workers=1 --console=plain: pass, 91 actionable tasks, BUILD SUCCESSFUL in 37s.
- Release-like validation used isolated detached worktree /home/brandon/worktrees/kite-revenge-validate-4dfda8a3 at exact superproject commit 4dfda8a3ce28b92220d79ed6bc5a76ec5c84ffa0; Matrix Rust SDK pinned to 128049fd3b183f059fb76402c82ce56ba7ddcd37.
- Initial :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon --max-workers=1 --console=plain outlived the connector call. A replayed duplicate Gradle writer was detected and terminated, leaving the original single writer to finish. Exact-command cached verification then reported BUILD SUCCESSFUL in 3s, 275 actionable tasks (10 executed / 265 up-to-date).
- Final APK: /home/brandon/worktrees/kite-revenge-validate-4dfda8a3/androidApp/build/outputs/apk/PerfDebug/androidApp-PerfDebug.apk, 107,853,803 bytes, SHA-256 d68c781c60c69ca0598f354a73425b9b186f68f86a102c8a96da775b41da7d00.
- AAPT: package app.kite.revenge.debug, label Kite, version perfdebug-26.10.14, target SDK 37, native code arm64-v8a.
- APK signature verified with existing V2 signer SHA-256 011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd.
- Samsung <private-adb-device> preflight/postflight found neither production app.kite nor redundant app.kite.revenge; only app.kite.revenge.debug was targeted. adb install -r returned Success.
- Existing debug app data/login was preserved: dataDir=/data/user/0/app.kite.revenge.debug, firstInstallTime=2026-10-14 11:55:12; post-install lastUpdateTime=2026-10-15 02:24:44.
- Device remained mWakefulness=Dozing / mHalInteractiveModeEnabled=false; Kite was not launched and the phone was not woken merely for QA.
- The pre-existing hide-room work remains unstaged and byte-for-byte unchanged:
  - InboxViewModel.kt SHA-256 cdaf2fb2a102299080109a6e7175925aed348fa92a7c1edd7679d8f6367394d7
  - AppStateStore.kt SHA-256 7571871842868354b4f23e8f63d6e2e8317d8eef461bc565e14660ecf3347673
  - strings.xml SHA-256 dafd5af2280836f57325a5dc11b099be8045d0705001ef08839b5a59a1330b4a

### Next substantial slice
- When the Samsung is naturally awake/unlocked, compare the installed build side-by-side with installed Google Messages across Inbox -> Conversation -> search -> composer focus/keyboard -> long-press selection, verifying that the removed circular loading chrome and app-bar crossfades eliminate the reported flash/jolt.
- Capture controlled gfxinfo/frame evidence during repeated Inbox <-> Conversation navigation, long-history scrolling, right-swipe reply, and left-swipe timestamp reveal at 120 Hz before making a measurable performance-parity claim.
- Continue the adjacent Google-Messages-style composer/reply/edit/attachment and reaction/action-sheet dark-theme polish from the observed device state, keeping the bottom inbox search exception and existing Matrix behavior intact.

## 2026-10-15 02:57 NZDT — Messages composer, reply/edit context, attachments, and split action surfaces

### Visual / interaction reference
- Re-read the pinned Google Messages reference mapping in docs/design-reference/google-messages/README.md before changing this slice, especially 05-material3-chat.webp and 06-dark-attachment-menu.webp.
- The pinned chat reference uses a rounded composer capsule with a distinct trailing send/action affordance; the dark attachment reference uses compact fixed circular action cells with labels rather than stretched full-width buttons.
- Cross-checked the current stable Google Messages long-press treatment: the reaction strip is visually separate from the rounded vertical action card. Kite keeps its existing five custom quick reactions plus Add Reaction and Matrix-specific actions rather than cloning Google-only capabilities.
- Preserved the intentional Kite exception unchanged: Inbox search remains at the bottom.
- The Samsung stayed Dozing / non-interactive, so installed Google Messages was not opened or mutated and no fresh side-by-side screenshot claim is made.

### Implemented
- Reworked the normal composer trailing action to match the current Messages structure without changing Matrix sending:
  - when the draft is sendable, a dedicated 48 dp circular primary Send button appears beside the existing 28 dp composer capsule;
  - send-in-progress keeps the same trailing geometry but disables the button, avoiding a layout jump;
  - IME Send and the button both continue through the existing ComposerViewModel.sendMessage(...) path;
  - no new send state, collector, animation, or parallel Matrix pipeline was introduced.
- Reworked reply/edit context presentation inside the composer:
  - reply and edit modes now share a narrow 3 dp accent rail and tighter hierarchy;
  - composer reply previews use a tonal surfaceContainerHighest treatment instead of nesting a second outlined bubble inside the composer;
  - ordinary timeline reply rendering remains unchanged because the new reply-preview mode is opt-in.
- Restyled the Camera / Gallery / File attachment sheet against the pinned dark Messages reference:
  - fixed 64 dp circular action cells,
  - 72 dp action columns with 20 dp spacing,
  - body-medium labels,
  - existing picker order/capabilities and platform file-picker pathways preserved.
- Split message long-press visuals into two deliberate surfaces:
  - the quick-reaction row is now its own surfaceContainerHighest pill;
  - the ordinary message actions are rendered in a separate surfaceContainerHigh rounded card below it;
  - unselected reaction cells are transparent inside the pill, selected reactions retain primaryContainer, and compact targets remain 44 dp;
  - the existing Android non-focusable popup behavior and second-long-press partial-text-selection plumbing remain intact.
- Performance/hot-path review:
  - no Matrix collector or duplicate timeline/draft state was added;
  - no new animation/effect loop was added;
  - the small reaction/action partition allocations occur only while the message popup is actually composed/open, not for closed rows while scrolling.

### Validation
- Cohesive source checkpoint: dbd57198c788ee12ee6cb3061e4121d04fef0505 (Polish Messages composer and action surfaces), 4 source files, 197 insertions / 57 deletions.
- git diff --check: pass before checkpoint.
- Glass with JDK 25 + Android SDK:
  - :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop --no-daemon --max-workers=1 --console=plain: pass, BUILD SUCCESSFUL in 37s;
  - full :composeApp:desktopTest --no-daemon --max-workers=1 --console=plain: pass, BUILD SUCCESSFUL in 7s.
- Release-like validation used isolated detached worktree /home/brandon/worktrees/kite-revenge-validate-dbd57198 at exact superproject commit dbd57198c788ee12ee6cb3061e4121d04fef0505; Matrix Rust SDK pinned to 128049fd3b183f059fb76402c82ce56ba7ddcd37.
- The initial clean :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon --max-workers=1 --console=plain outlived the connector foreground window. A replay created one duplicate Gradle writer; only the newer duplicate was terminated, the original completed and produced the APK, and an exact-command cached verification then reported BUILD SUCCESSFUL in 3s with 275 actionable tasks.
- Final clean APK: /home/brandon/worktrees/kite-revenge-validate-dbd57198/androidApp/build/outputs/apk/PerfDebug/androidApp-PerfDebug.apk, 107,853,803 bytes, SHA-256 14f007bd4eb6fddc87d2d4078f106bf1a0076581118bcd8f7ce2fe7dc40f42b4.
- AAPT: package app.kite.revenge.debug, label Kite, version perfdebug-26.10.14, target SDK 37, native code arm64-v8a.
- APK signature verified with existing V2 signer SHA-256 011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd.
- Samsung <private-adb-device> preflight/postflight found only app.kite.revenge.debug among app.kite* packages. The exact verified APK was installed with adb install -r and returned Success; no app.kite.revenge release package was created or installed.
- Debug data/login was preserved: dataDir=/data/user/0/app.kite.revenge.debug, firstInstallTime=2026-10-14 11:55:12, post-install lastUpdateTime=2026-10-15 02:56:53.
- Post-install device state remained mWakefulness=Dozing / mHalInteractiveModeEnabled=false; Kite and Google Messages were not launched and the phone was not woken merely for QA.
- No 120 Hz frame-time or side-by-side visual-parity claim is made for this slice.
- The pre-existing hide-room work remains unstaged and byte-for-byte unchanged:
  - InboxViewModel.kt SHA-256 cdaf2fb2a102299080109a6e7175925aed348fa92a7c1edd7679d8f6367394d7
  - AppStateStore.kt SHA-256 7571871842868354b4f23e8f63d6e2e8317d8eef461bc565e14660ecf3347673
  - strings.xml SHA-256 dafd5af2280836f57325a5dc11b099be8045d0705001ef08839b5a59a1330b4a

### Next substantial slice
- When the Samsung is naturally awake/unlocked, compare the exact installed PerfDebug build side-by-side with installed Google Messages:
  - empty/focused/typed composer geometry, dedicated send button and keyboard/insets;
  - reply/edit context rail and long reply previews;
  - dark attachment sheet spacing and Camera / Gallery / File action cells;
  - long-press quick-reaction pill versus the separate action card, action taps, popup dismissal, and second-long-press partial text selection.
- Capture controlled gfxinfo/frame evidence during long-history scrolling, composer focus/typing, long-press actions, and Inbox <-> Conversation navigation at an actually active 120 Hz mode before making a measurable performance-parity claim.
- After that observed QA, continue the next broad Google-Messages-style surface: message bubble/timeline metadata and media presentation, then search/settings/account surfaces, while preserving the bottom Inbox search exception and existing Matrix behavior.

## 2026-10-15 03:26 NZDT — Messages bubble grouping, media cards, timeline density, and waveform hot-path cleanup

### Visual / interaction reference
- Re-read the pinned Google Messages mapping in docs/design-reference/google-messages/README.md and inspected 01-official-conversation.png, 05-material3-chat.webp, and 06-dark-attachment-menu.webp before changing the timeline.
- The pinned conversation references keep nearby same-sender bubbles as individually rounded pills with compact vertical grouping rather than Revenge-style sharp joined corners; successful messages also remain free of permanent in-bubble timestamps.
- Preserved Kite identity/colors and Matrix-specific reactions/read receipts rather than copying Google branding or removing Matrix capabilities.
- Preserved the deliberate product exception unchanged: Inbox search remains at the bottom.
- The Samsung was still Dozing / non-interactive, so installed Google Messages was not opened or mutated merely for reference gathering and no fresh side-by-side visual-parity claim is made.

### Implemented
- Reworked conversation bubble grouping and timeline rhythm toward the pinned Messages references:
  - same-sender runs now keep the full 20 dp bubble radius instead of collapsing joined corners to 6 dp;
  - compact same-sender spacing is 4 dp and sender-boundary spacing is 12 dp;
  - date separators use a quieter bodySmall treatment with 16 dp vertical breathing room;
  - successful messages continue to avoid permanent timestamps, preserving the existing swipe-to-reveal/status behavior.
- Reworked image/video presentation:
  - image/video content now reaches the rounded bubble edge instead of carrying the old 2 dp Revenge inset;
  - captions use the same 14 x 9 dp content inset as text bubbles;
  - video playback uses a 40 dp tonal Material play affordance with a 24 dp icon instead of the opaque inverse-color 32 dp disk.
- Reworked file/audio/voice cards into a consistent attachment system:
  - shared 40 dp tonal attachment icon treatment with 10 dp icon inset;
  - stable 176 dp file-card and 220 dp audio-card minimum widths;
  - long filenames are bounded to two lines;
  - caption spacing no longer doubles the outer Arrangement.spacedBy(...) gap;
  - cards use the normal Messages-style bubble content padding instead of the old 8 dp Revenge inset.
- Tightened Matrix-specific metadata surfaces without removing behavior:
  - reaction rows/chips use denser 4/2 dp row spacing and 9/4 dp inner padding with labelMedium counts;
  - read-receipt vertical spacing is reduced from 4 dp to 2 dp.
- Performance hot-path cleanup for voice/audio messages:
  - removed snapshot-state writes from inside the waveform Canvas draw pass;
  - waveform width is now captured only by onSizeChanged;
  - resampling is remembered by the bounded display sample count and uses the actual line-width + line-padding step;
  - sample count is clamped to the existing 64-segment rendering budget.
- Added focused regression coverage for full-radius grouped bubbles and waveform sample-count bounds.
- No new Matrix collector, duplicated timeline state, animation/effect loop, or blocking UI work was introduced.

### Validation
- Cohesive source checkpoint: 139aae3e5e852b7173ff2ed9ae51c864eaf44c7a (Polish Messages timeline and media bubbles), 9 files, 113 insertions / 85 deletions.
- git diff --check: pass before checkpoint.
- Focused MessageBubbleShapeTest + AudioWaveformLayoutTest: pass with JDK 25 (BUILD SUCCESSFUL in 27s).
- Glass with JDK 25 + /opt/android-sdk: :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop :composeApp:desktopTest --no-daemon --max-workers=1 --console=plain: pass (BUILD SUCCESSFUL in 28s, 91 actionable tasks).
- Release-like validation reused the clean detached validation worktree /home/brandon/worktrees/kite-revenge-validate-dbd57198, checked out at exact superproject commit 139aae3e5e852b7173ff2ed9ae51c864eaf44c7a; Matrix Rust SDK remained pinned to 128049fd3b183f059fb76402c82ce56ba7ddcd37.
- :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon --max-workers=1 --console=plain: pass (BUILD SUCCESSFUL in 1m 7s, 279 actionable tasks).
- Final clean APK: /home/brandon/worktrees/kite-revenge-validate-dbd57198/androidApp/build/outputs/apk/PerfDebug/androidApp-PerfDebug.apk, 107,853,803 bytes, SHA-256 01d79a78f9734418b6952adf19caeb3264b50fde0acb70aab0595210d069a950.
- AAPT verifies package app.kite.revenge.debug, label Kite, version perfdebug-26.10.14, target SDK 37, native code arm64-v8a.
- APK signature verified with the existing V2 signer SHA-256 011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd.
- Samsung <private-adb-device> preflight found neither production app.kite nor redundant app.kite.revenge; only app.kite.revenge.debug was targeted. adb install -r returned Success.
- Existing debug data/login was preserved: dataDir=/data/user/0/app.kite.revenge.debug, firstInstallTime=2026-10-14 11:55:12; post-install lastUpdateTime=2026-10-15 03:24:15.
- Post-install device state remained mWakefulness=Dozing / mHalInteractiveModeEnabled=false; Kite and Google Messages were not launched and the phone was not woken merely for QA.
- No 120 Hz frame-time or fresh side-by-side visual-parity claim is made for this slice.
- The pre-existing hide-room work remains unstaged and byte-for-byte unchanged:
  - InboxViewModel.kt SHA-256 cdaf2fb2a102299080109a6e7175925aed348fa92a7c1edd7679d8f6367394d7
  - AppStateStore.kt SHA-256 7571871842868354b4f23e8f63d6e2e8317d8eef461bc565e14660ecf3347673
  - strings.xml SHA-256 dafd5af2280836f57325a5dc11b099be8045d0705001ef08839b5a59a1330b4a

### Next substantial slice
- When the Samsung is naturally awake/unlocked, compare the exact installed PerfDebug build side-by-side with installed Google Messages across long and short text runs, image/video bubbles, file/audio/voice cards, reactions, read receipts, dates, dark mode, and swipe-to-reveal metadata; capture controlled 120 Hz gfxinfo evidence before claiming measurable parity.
- Continue the next broad Google-Messages-style surface even if device visual QA is still unavailable: search/results/navigation first, then settings/account rows, dialogs and toggles using the pinned reference set and existing native Revenge state/navigation paths.
- Keep the Inbox search bar at the bottom and preserve all Matrix-specific behavior while avoiding per-row collectors, parallel state systems, and decorative animation.


## 2026-10-15 04:28 NZDT — Messages inbox container, row hierarchy, and scroll hot-path cleanup

### Visual / interaction reference
- Re-read the pinned Google Messages reference mapping in docs/design-reference/google-messages/README.md before changing the inbox, especially the inbox-branding and Material 3 overview references.
- Cross-checked current public Google Messages Material 3 Expressive homepage coverage: the conversation list is presented as one rounded container, with larger contact imagery and clearer separation between the app/status chrome and the list surface.
- Preserved Kite identity, Matrix unread/status semantics, and the deliberate product exception unchanged: the inbox search bar remains at the bottom.
- The Samsung remained Dozing / non-interactive, so installed Google Messages was not opened or mutated merely for reference gathering and no fresh side-by-side visual-parity claim is made.

### Implemented
- Reworked the inbox shell as a single Messages-like tonal hierarchy:
  - the destination background uses surfaceContainer;
  - room/loading/empty content sits inside one 28 dp rounded surface;
  - the room list has 8 dp internal vertical breathing room while retaining the existing bottom-search reservation and keyboard/inset behavior.
- Reworked room-row sizing and information hierarchy:
  - room avatars increased from 48 dp to 52 dp;
  - rows use an 80 dp minimum touch/layout height with 10 dp vertical inset;
  - the name/timestamp line is cleaner and timestamp emphasis becomes primary for unread rooms, otherwise onSurfaceVariant;
  - draft, mute, low-priority and favorite Matrix indicators move to the preview line rather than competing with the timestamp;
  - unread badge sizing is centralized at a 20 dp minimum and existing count/mention semantics remain intact.
- Added a Messages-style tonal create-room action in the inbox app bar while keeping TopNavigationIcon backward-compatible through an opt-in tonal parameter.
- Brought Matrix-specific adjacent surfaces into the same visual system:
  - space-selector fallback surfaces use neutral surfaceContainer / onSurfaceVariant roles instead of stronger Revenge secondary-container styling;
  - pending forward and incoming-share notices use 24 dp surfaceContainerHighest cards without the old outline;
  - notice dismissal uses a proper 40 dp Material IconButton target while preserving keyboard focus actions.
- Performance/hot-path cleanup:
  - inbox-wide dual-mention unread preferences are now collected once at inbox scope and passed into rows instead of reading the preference separately in every row;
  - visible-room subscription observation no longer allocates a list of every visible index on each scroll observation; it tracks only first/last visible indices in one packed value, debounces, then passes a subList view;
  - removed the unrelated accountsSorted dependency from that scroll observation effect;
  - no new Matrix collector, duplicated room state, animation loop, or blocking UI work was introduced.

### Validation
- Cohesive source checkpoint: c7eb9ce591717734652479cca6b9c1326d1a7592 (Polish Messages inbox surface and rows), 8 source files, 190 insertions / 108 deletions.
- git diff --check: pass.
- Glass with JDK 25 + /opt/android-sdk:
  - :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop --no-daemon --max-workers=1 --console=plain: pass, BUILD SUCCESSFUL in 37s;
  - after the hot-path cleanup, :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop :composeApp:desktopTest --no-daemon --max-workers=1 --console=plain: pass, BUILD SUCCESSFUL in 38s, 91 actionable tasks.
- Release-like validation reused clean detached worktree /home/brandon/worktrees/kite-revenge-validate-dbd57198, checked out at exact superproject commit c7eb9ce591717734652479cca6b9c1326d1a7592; Matrix Rust SDK remained pinned to 128049fd3b183f059fb76402c82ce56ba7ddcd37.
- :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon --max-workers=1 --console=plain: pass, BUILD SUCCESSFUL in 1m 6s, 279 actionable tasks.
- Exact clean APK: /home/brandon/worktrees/kite-revenge-validate-dbd57198/androidApp/build/outputs/apk/PerfDebug/androidApp-PerfDebug.apk, 107,870,187 bytes, SHA-256 1626f6caca46c68862e07cae3764f9d233759f6e465e357160afc2e013fc93ce.
- AAPT verifies package app.kite.revenge.debug, label Kite, version perfdebug-26.10.14, target SDK 37, and native code arm64-v8a.
- APK signature verified with the existing V2 signer SHA-256 011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd.
- Samsung <private-adb-device> preflight/postflight found only app.kite.revenge.debug among app.kite* packages; production app.kite and redundant app.kite.revenge were not targeted or installed.
- The verified PerfDebug APK was replaced in place with adb install -r; postflight confirms dataDir=/data/user/0/app.kite.revenge.debug, unchanged firstInstallTime=2026-10-14 11:55:12, and updated lastUpdateTime=2026-10-15 04:25:29, preserving the existing debug app data/login.
- Device state remained mWakefulness=Dozing / mHalInteractiveModeEnabled=false; Kite and Google Messages were not launched and the phone was not woken merely for QA.
- No fresh side-by-side visual-parity or 120 Hz frame-time claim is made for this slice.
- The pre-existing hide-room work remains unstaged and byte-for-byte unchanged:
  - InboxViewModel.kt SHA-256 cdaf2fb2a102299080109a6e7175925aed348fa92a7c1edd7679d8f6367394d7
  - AppStateStore.kt SHA-256 7571871842868354b4f23e8f63d6e2e8317d8eef461bc565e14660ecf3347673
  - strings.xml SHA-256 dafd5af2280836f57325a5dc11b099be8045d0705001ef08839b5a59a1330b4a

### Next substantial slice
- When the Samsung is naturally awake/unlocked, compare the exact installed PerfDebug build side-by-side with installed Google Messages across inbox shell curvature, 52 dp avatars, row density, unread/timestamp hierarchy, Matrix status indicators, bottom-search geometry, dark mode, long names/previews, and transient share/forward cards.
- Capture controlled 120 Hz gfxinfo/frame evidence during long inbox scrolling, search focus/type/clear, and Inbox <-> Conversation navigation before making a measurable performance-parity claim.
- Continue the next broad native surface while device visual QA is unavailable: create-room/start-chat and search-result presentation, then remaining account/profile/dialog details and dark/accessibility polish, preserving existing Matrix state/navigation paths and the bottom Inbox search exception.


## 2026-10-15 05:20 NZDT — native Start chat, search-results, and create-room Messages surface

1. Continued directly from the 04:28 inbox checkpoint using the committed Google Messages reference set under `docs/design-reference/google-messages`, especially `04-inbox-branding.jpg`, `02-material3-expressive-overview.webp`, and the README's explicit bottom-search exception. The connected Samsung remained dozing/non-interactive, so installed Google Messages was not opened merely for reference gathering and no SMS/RCS state was touched.
2. Completed the next broad inbox/search surface instead of stopping at a cosmetic tweak. Inbox search is now consistently bottom-anchored at compact and wide widths, the room list reserves its bottom inset for that control, typed search results get a `Conversations` hierarchy label, and empty/loading search presentation now uses deliberate Material 3 icon/progress surfaces rather than the stock Revenge placeholder card. A 56 dp tonal `Start chat` action sits above the bottom search bar in the same lower-action region as the pinned Messages reference.
3. Added a real native `StartChat` destination rather than routing the new affordance through generic room creation. Its Compose surface has a rounded Messages-style people search field, optional account chips for multi-account sessions, a separate `Create new room` tonal action, explicit idle/loading/error/no-results states, and 76 dp result rows with 52 dp circular avatars, name/MXID hierarchy, and bounded progress feedback. Destination serialization/keybinding parsing and normal window sizing were integrated into the existing navigation system.
4. `StartChatViewModel` reuses MatrixClient state rather than introducing a parallel Matrix model. People search is debounced by 220 ms and cancellation-aware; it calls the existing homeserver `searchUsers` path, supplements an exact valid MXID with `getProfile` when directory search omits it, de-duplicates by user ID, and exposes one shared search state rather than per-row flows. Starting a chat reuses `startDM`, so an existing direct room is found first and a new encrypted trusted-private direct room is created only when needed; success replaces the picker with the existing Conversation destination.
5. Tightened state/dispatcher ownership after validating the SDK implementation. Matrix Rust-backed `searchUsers`, `getProfile`, `findDM`, and room creation already switch through the client's session dispatcher, so the extra UI-side IO dispatch was removed. Navigation/error delivery now remains on the ViewModel main scope, and account selection falls back to a live account if the requested session disappears. This keeps the new flow off inbox/message hot paths and adds no per-message/per-result collectors, animation layers, blur, or duplicated room state.
6. Restyled advanced room creation as the companion Matrix-specific surface: rounded-top container, grouped 20 dp tonal editor/setting cards, start-aligned label hierarchy, spaced toggle rows, and a full-width 56 dp rounded create button. Name/topic editing, visibility/encryption/advanced controls and existing room-creation behavior remain on Revenge/Matrix pathways.
7. Source checkpoints are `52a89d65` (`Add Messages-style native start chat flow`) and `cce98386` (`Keep start-chat UI work on main dispatcher`). The pre-existing unfinished hide-chat edits in `InboxViewModel.kt`, `AppStateStore.kt`, and the three hide-chat strings were kept out of both commits and remain unstaged.
8. Source validation on Glass with JDK 25 and `/opt/android-sdk`: `git diff --check` PASS; `:composeApp:compileAndroidMain :composeApp:compileKotlinDesktop :composeApp:desktopTest --no-daemon --max-workers=1 --console=plain` PASS after the final dispatcher polish (`BUILD SUCCESSFUL in 38s`, 91 actionable tasks). Earlier all-ABI packaging attempts exposed generated-output/art-profile races, so release-like validation used the established arm64-only clean-worktree path rather than treating those build-system races as source failures.
9. Release-like validation used clean detached worktree `/home/brandon/worktrees/kite-revenge-validate-dbd57198` at exact superproject commit `cce9838622285f207d59abe28bc79b89a00bbe82`, with Matrix Rust SDK pinned to `128049fd3b183f059fb76402c82ce56ba7ddcd37`. `:androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon --max-workers=1 --console=plain` PASS (`BUILD SUCCESSFUL in 1m 4s`, 279 actionable tasks).
10. Exact final APK: `/home/brandon/worktrees/kite-revenge-validate-dbd57198/androidApp/build/outputs/apk/PerfDebug/androidApp-PerfDebug.apk`, 107,886,711 bytes, SHA-256 `0bcb5e62807a86cbf83509f7e39dcb12897e3a192f42dea560a3cb3411fc1d0d`. AAPT reports package `app.kite.revenge.debug`, label `Kite`, version `perfdebug-26.10.14`, target SDK 37 and native code `arm64-v8a`; the existing V2 signer SHA-256 remains `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd`.
11. Samsung `<private-adb-device>` safety proof: pre/post install found production `app.kite` absent and redundant `app.kite.revenge` absent; only `app.kite.revenge.debug` was replaced in place. The final exact APK installed successfully, `dataDir=/data/user/0/app.kite.revenge.debug` and `firstInstallTime=2026-10-14 11:55:12` stayed unchanged, while `lastUpdateTime` advanced to `2026-10-15 05:19:12`. The existing debug data/login was therefore preserved.
12. Fresh device visual/performance QA is deliberately not claimed. After installation the Samsung still reported `mWakefulness=Dozing` and `mHalInteractiveModeEnabled=false`; Kite and Google Messages were not launched merely to manufacture screenshots. There is no new 120 Hz frame-time result for this slice.

### Next substantial slice
- When the Samsung is naturally awake/unlocked, compare this exact installed build side-by-side with installed Google Messages across Start chat, typed/no-result people search, multi-account selection, create-room grouping, bottom inbox search geometry, dark mode, long names/MXIDs, and IME/inset behavior; fix measured mismatches in the same run.
- Capture controlled `gfxinfo`/frame evidence for inbox search + navigation and Start-chat result scrolling at an active 120 Hz mode before making a measurable performance-parity claim.
- Continue the next broad native Messages-style surface even if device QA is still unavailable: settings/account rows, dialogs/toggles and remaining profile/account selection details, preserving all Matrix-specific capabilities and existing native state/navigation paths.

## 2026-10-15 05:34 NZDT — Messages Start-chat refinement + settings/account tonal system

### Visual / interaction reference
- Continued from the committed Google Messages reference set in docs/design-reference/google-messages, especially the Material 3 Expressive overview/settings and inbox references, and cross-checked current public Google Messages coverage showing rounded result/contact containers and rounded per-setting containers.
- Preserved Kite identity and Matrix-only controls. The intentional Inbox exception remains unchanged: search stays at the bottom.
- The Samsung stayed Dozing / non-interactive for the entire device checkpoint, so installed Google Messages was not opened merely to gather screenshots and no SMS/RCS state was touched.

### Implemented
- Refined the already-native Start-chat flow into a more coherent Messages-style people picker:
  - 24 dp search/result containers and 20 dp contact cards;
  - clearer surface-container tonal hierarchy;
  - compact 68 dp rows with 44 dp avatars and name/MXID hierarchy;
  - explicit contentType for result rows to keep lazy reuse stable;
  - loading/empty/failure surfaces now use the same tonal system.
- Tightened shared search chrome icon/text spacing without moving or altering the bottom Inbox search placement.
- Brought Matrix room creation into the same navigation and tonal treatment:
  - leading back navigation, 28 dp rounded-top content panel, 24 dp setting/editor cards, denser create action;
  - moved available-session collection and advanced-settings coroutine scope out of LazyColumn item composition;
  - memoized session dropdown entries, reducing avoidable lazy-item state/collector work.
- Reworked settings as a Messages-style tonal hierarchy:
  - surfaceContainer destination chrome -> rounded-top surfaceContainerLow content panel -> 20 dp surfaceContainerHigh preference cards;
  - 68/80 dp minimum row heights and calmer category spacing while retaining existing Material switches/sliders and native preference persistence.
- Reworked account management in the same system:
  - rounded-top content panel plus 24 dp account/login cards and 52 dp account avatars;
  - visible Matrix verification status text beside its status glyph instead of tooltip-only status;
  - 40 dp error-container logout affordance;
  - explicit account lazy-list contentType;
  - removed the decorative AnimatedContent around homeserver login controls so account state changes are direct and allocation/animation-free.
- No new Matrix state stack, per-room/per-message collectors, blur/effect loops, or blocking UI work were introduced.

### Validation
- Cohesive source checkpoint: 48ed5b390c2883a2b9162168fe7acf48ecf4812d (Polish Messages start chat and settings surfaces), 6 files, 300 insertions / 212 deletions.
- git diff --check: pass.
- Glass, JDK 25 + /opt/android-sdk: :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop :composeApp:desktopTest --no-daemon --max-workers=1 --console=plain: pass, BUILD SUCCESSFUL in 38s, 91 actionable tasks.
- Clean detached validation worktree /home/brandon/worktrees/kite-revenge-validate-dbd57198 checked out at exact source commit 48ed5b390c2883a2b9162168fe7acf48ecf4812d; Matrix Rust SDK remained pinned to 128049fd3b183f059fb76402c82ce56ba7ddcd37.
- :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon --max-workers=1 --console=plain: pass, BUILD SUCCESSFUL in 1m 4s, 279 actionable tasks.
- Exact APK: /home/brandon/worktrees/kite-revenge-validate-dbd57198/androidApp/build/outputs/apk/PerfDebug/androidApp-PerfDebug.apk, 107,886,711 bytes, SHA-256 e06a15e74a9b5eab4ea2e5d3fb1bba6fb2862c90087f0f1c918cab4783b0b5e9.
- AAPT: package app.kite.revenge.debug, label Kite, version perfdebug-26.10.14, target SDK 37, native code arm64-v8a.
- APK signature: V2 signer SHA-256 011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd.
- Samsung <private-adb-device> preflight found only app.kite.revenge.debug among Kite packages. adb install -r returned Success; post-install dataDir=/data/user/0/app.kite.revenge.debug, firstInstallTime=2026-10-14 11:55:12 remained unchanged, and lastUpdateTime=2026-10-15 05:32:55.
- Device remained mWakefulness=Dozing / mHalInteractiveModeEnabled=false; neither Kite nor Google Messages was launched for visual QA. No side-by-side visual-parity or 120 Hz performance claim is made.
- The unrelated local hide-room work remains unstaged and excluded from this checkpoint: InboxViewModel.kt, AppStateStore.kt, and the three hide-chat/undo strings.

### Next substantial slice
- When the Samsung is naturally awake/unlocked, compare this exact installed PerfDebug build side-by-side with Google Messages across Start chat, create-room, Settings and account management in light/dark mode, including long names/MXIDs, switches, login fields, keyboard/insets and back navigation; fix concrete mismatches in the same run.
- Capture controlled 120 Hz frame evidence for Inbox search/navigation and Start-chat result scrolling before claiming measurable performance parity.
- Continue remaining profile/account-selection dialogs and transient surfaces, then return to notification quick-reply/actions and controlled message/composer E2E while preserving the bottom Inbox search exception and all Matrix behavior.


## 2026-10-15 — Google Messages profile/account-selection and transient-action slice

### Visual reference
- Used the pinned Google Messages / Material 3 Expressive reference set in docs/design-reference/google-messages because the Samsung was dozing/locked and was not woken for reference gathering.
- Preserved the intentional Kite exception: inbox search remains at the bottom.

### Implemented
- Restyled SessionSelectorScreen into the same Messages-style tonal hierarchy used by settings/account management: surfaceContainer chrome, 28 dp rounded surfaceContainerLow content, and 20 dp surfaceContainerHigh account cards.
- Account-selection rows now use 72 dp minimum touch height, 48 dp avatars, stronger name/MXID hierarchy, trailing navigation affordance, stable lazy-list content type, and a dedicated error-container failure state.
- Fixed account destination resolution failures so the screen clears its processing state instead of remaining stuck after an error.
- Restyled UserDetailsScreen with a 28 dp rounded content panel and 24 dp high-tonal profile hero, 96 dp avatar, headline/body identity hierarchy, and stable lazy item content types.
- Replaced flat mutual-room text with 20 dp tonal disclosure/room cards, a tonal group icon, expand affordance, 44 dp room avatars, and preserved Matrix navigation/copy actions.
- Restyled MessageSelectionMoreSheet into compact 20 dp tonal action cards with 40 dp icon wells; destructive report/delete actions now use error-container hierarchy.
- Restyled MessageInfoSheet metadata and event-source surfaces into matching 20 dp high-tonal cards.
- No new per-row collectors, duplicated Matrix state, or animations were introduced.

### Validation so far
- git diff --check: PASS.
- Java 25 :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop: PASS.
- Java 25 :composeApp:desktopTest: PASS.
- The initial build attempt used Glass's default Java 17 and failed at dependency configuration because Metro requires Java 21+; rerunning with /usr/lib/jvm/java-25-openjdk passed.
- Samsung SM-S931B remained dozing/locked during implementation, so no wake/launch or Google Messages state mutation was performed and no device visual/120 Hz parity claim is made yet.

### Next
- Produce and verify the release-like PerfDebug APK from a clean detached checkout of this checkpoint, confirm package/signature identity, and install only app.kite.revenge.debug if safe.
- When the Samsung is naturally awake/unlocked, compare account selection/profile/transient actions side-by-side with Google Messages and capture 120 Hz frame evidence.
- Continue into the adjacent notification quick-reply/action verification and remaining room/profile detail surfaces.


### PerfDebug validation completion
- Clean detached validation checkout at commit a579db9d with Matrix Rust SDK pin 128049fd3b183f059fb76402c82ce56ba7ddcd37.
- Java 25 :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a: PASS.
- APK identity: app.kite.revenge.debug, native-code arm64-v8a.
- APK signing SHA-256: 011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd.
- Replace-install on Samsung SM-S931B: PASS; dataDir remained /data/user/0/app.kite.revenge.debug and firstInstallTime remained 2026-10-14 11:55:12. lastUpdateTime became 2026-10-15 06:06:57.
- The app was not launched after installation and the Samsung remained dozing, preserving device/user state. Side-by-side visual QA and 120 Hz frame measurement remain intentionally deferred until the device is naturally awake/unlocked.


## 2026-10-15 06:38 NZDT — Messages room details, members, reactions, and receipts

### Visual / interaction reference
- Re-read the pinned Google Messages mapping in docs/design-reference/google-messages/README.md and used the committed Material 3 Expressive settings/detail references as the stable baseline for rounded content panels, per-row tonal containers, profile/detail navigation and compact metadata pills.
- Cross-checked current public Google Messages Material 3 Expressive coverage showing rounded containers for details/settings surfaces and pill-like detail actions rather than flat Revenge rows.
- Preserved Kite identity, Matrix-specific room metadata/actions, and the deliberate Inbox exception unchanged: search remains at the bottom.
- The Samsung remained Dozing / non-interactive, so installed Google Messages was not opened or mutated merely for reference gathering and no fresh side-by-side claim is made.

### Implemented
- Reworked RoomDetailsScreen into the same Messages-style tonal hierarchy now used across Settings and profile surfaces:
  - surfaceContainer destination chrome -> 28 dp rounded-top surfaceContainerLow content panel -> 20 dp surfaceContainerHigh detail/editor cards;
  - 8 dp list rhythm and 16 x 14 dp card padding;
  - room name, topic and private-name editors now sit in deliberate tonal cards rather than floating on the page;
  - aliases, join rule, history visibility, room ID/type/version/predecessor and bridge metadata retain their existing copy/edit/navigation behavior but share one visual system;
  - public/private/direct/encryption badges now use compact 16 dp surfaceContainerHighest pills instead of conversation-bubble styling.
- Moved joinRuleRoomNames collection from inside a LazyColumn item to screen scope, avoiding lazy-item collector creation/recreation while preserving the existing Matrix state source.
- Reworked RoomMembersScreen:
  - matching rounded-top low-tonal panel and intentional loading/empty states;
  - 12 dp list inset, 8 dp row spacing, stable room-member contentType;
  - shared user rows now use 20 dp high-tonal cards, 72 dp minimum touch height and 48 dp avatars;
  - removed accidental reuse of the outer row modifier on AvatarImage, preventing duplicated row modifiers from being applied to avatars.
- Matrix-specific member role/power-level and non-joined membership states now render as compact 12 dp tonal pills in a FlowRow instead of stacked secondary text.
- Applied the same detail-list system to message reactions and read receipts, including stable lazy content types and the shared 72 dp user-row treatment.
- Changed the shared conversation-detail app-bar affordance from a Close X to an auto-mirrored back arrow while preserving the existing closeScreen navigation semantics for normal and split-pane layouts.
- Audited Android notification actions without replacing working native behavior:
  - inline RemoteInput reply, mark-as-read and conservative Copy code actions remain present;
  - quick reply sends through the joined room live timeline, then updates private/full read markers only after a successful send;
  - NotificationActionReceiver remains non-exported and uses goAsync for the asynchronous Matrix work.
- No new per-row Matrix collectors, duplicated room state, blur/effect loops or decorative animations were introduced.

### Validation
- Cohesive source checkpoint: 1dc65e0399c07bb36b482a7f6ea0f576bb69cee8 (Polish Messages room detail surfaces), 7 files, 357 insertions / 219 deletions.
- git diff --check and staged diff check: pass.
- Glass with JDK 25 + /opt/android-sdk: :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop :composeApp:desktopTest --no-daemon --max-workers=1 --console=plain: pass after the final slice, BUILD SUCCESSFUL in 34s, 87 actionable tasks.
- Clean detached validation worktree /home/brandon/worktrees/kite-revenge-validate-dbd57198 checked out at exact source commit 1dc65e0399c07bb36b482a7f6ea0f576bb69cee8; Matrix Rust SDK remained pinned to 128049fd3b183f059fb76402c82ce56ba7ddcd37.
- :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon --max-workers=1 --console=plain: pass, BUILD SUCCESSFUL in 1m 3s, 279 actionable tasks.
- Exact APK: /home/brandon/worktrees/kite-revenge-validate-dbd57198/androidApp/build/outputs/apk/PerfDebug/androidApp-PerfDebug.apk, 107,886,711 bytes, SHA-256 79cd5eb7a14f6a71c5b3e27fa59dc849a3fb9863608be8af4d391790d0ac1241.
- AAPT verifies package app.kite.revenge.debug, label Kite, version perfdebug-26.10.14, target SDK 37 and native code arm64-v8a.
- APK signature verified with the existing V2 signer SHA-256 011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd.
- Samsung SM-S931B / <private-adb-device> preflight and postflight found only app.kite.revenge.debug among Kite packages. Production app.kite and redundant app.kite.revenge were not touched.
- adb install -r returned Success. dataDir remained /data/user/0/app.kite.revenge.debug and firstInstallTime remained 2026-10-14 11:55:12; lastUpdateTime advanced from 2026-10-15 06:06:57 to 2026-10-15 06:37:17, preserving debug data/login.
- The phone remained mWakefulness=Dozing / mHalInteractiveModeEnabled=false before and after installation. Neither Kite nor Google Messages was launched, no notification reply was sent, and no SMS/RCS state was touched.
- No fresh side-by-side visual-parity or 120 Hz frame-time claim is made for this slice.
- The unrelated in-progress device-local hide-room edits remain unstaged and excluded from this checkpoint: InboxViewModel.kt, AppStateStore.kt and the hide-chat/undo strings.

### Next substantial slice
- When the Samsung is naturally awake/unlocked, compare this exact installed PerfDebug build side-by-side with Google Messages across room details, member lists, reactions/read receipts, long names/MXIDs, dark mode and back navigation; fix concrete mismatches in the same run.
- Capture controlled 120 Hz frame evidence for detail-list scrolling and Inbox/Conversation/detail navigation before claiming measurable performance parity.
- Continue the adjacent Google-Messages-style room preview/join/invite and verification/dialog surfaces; perform controlled notification quick-reply/action E2E only when it can be done without disturbing production conversations or external recipients.
## 2026-10-15 07:09 NZDT — Google Messages room preview, verification, and transient notice slice

### Visual reference and scope
- Started from the pinned Google Messages reference set in docs/design-reference/google-messages and its README source mapping. This slice follows the already-established Material 3 treatment: surfaceContainer destination chrome, rounded 28 dp low-container content panels, high-tonal cards, circular avatars, strong title/secondary-text hierarchy, compact tonal metadata, and full-width rounded primary actions.
- The intentional Kite bottom-search exception is unchanged.
- The installed Google Messages app was not opened or mutated. The Samsung was in active use by Chrome/ChatGPT earlier in the run and was Dozing with NotificationShade focused after installation, so this run deliberately did not steal focus for reference gathering. No fresh side-by-side or visual-parity claim is made.

### Room preview / invite / join
- Reworked RoomPreviewScreen from the remaining flat Revenge presentation into the same Google-Messages-style destination hierarchy used by native Kite's room details:
  - surfaceContainer outer chrome with safe top/horizontal insets;
  - rounded-top 28 dp surfaceContainerLow content panel;
  - stable LazyColumn item keys/content types with 8 dp spacing and navigation-bar bottom inset;
  - 104 dp circular room avatar in a 28 dp surfaceContainerHigh hero card;
  - headline/alias hierarchy plus compact tonal room-type and membership pills;
  - 48 dp inviter avatar and inviter identity/details in a 20 dp high-tonal card;
  - existing mutual-room disclosure/list reused rather than duplicating state or navigation;
  - full-width 56 dp join action and full-width error-tonal reject-invite action;
  - via-server metadata moved into a rounded tonal card;
  - preview failure state now uses an intentional error-container card rather than bare centered text.
- Preserved RoomActionProvider join/leave handling, PendingAction tracking, inviter navigation, copy actions, mutual-room behavior, keyboard focus/action providers, and Matrix room state.
- Review caught and corrected a lazy-key interpolation mistake before validation; mutual room keys are now based on preview.id.

### Verification
- Reworked VerificationRequestScreen into the same native Messages-style shell and card hierarchy:
  - surfaceContainer chrome, back-style top navigation, rounded-top 28 dp surfaceContainerLow body;
  - keyed verification state items and navigation-bar inset handling;
  - metadata grouped into 20 dp surfaceContainerHigh cards;
  - verification identity rows changed from dense inline pairs to label/value hierarchy;
  - incoming verification avatar reduced to 88 dp and kept circular;
  - normal and critical state messages presented as tonal/error cards;
  - primary/critical actions are full-width 56 dp rounded buttons;
  - progress is contained in a tonal card;
  - SAS emoji comparison uses compact 20 dp secondaryContainer cards with 56 dp emoji assets.
- Existing verification request lifecycle and Matrix Rust SDK pathways remain intact: accept, cancel, SAS start, approve, mismatch/decline, completion and failure flows were not replaced.

### App-level transient messages
- Reworked AppMessages from flat animated rows into 20 dp rounded tonal cards with body/action hierarchy matching the rest of the native UI.
- Confirmation and verification prompts now use secondary TextButton + compact primary Button action rows while preserving keyboard actions, copying, dismissal and verification navigation/failure behavior.
- Removed the previous slide/expand/shrink AnimatedVisibility treatment. This reduces decorative work in this transient UI path; no broader performance-parity claim is made.

### Validation
- Cohesive source checkpoint: a3426d2e4825679548e3282a87d22a6f18b7264b (Polish Messages invite and verification surfaces), 3 files, 655 insertions / 443 deletions.
- git diff --check and staged diff check: pass.
- Glass with JDK 25 + /opt/android-sdk:
  - :composeApp:compileAndroidMain :composeApp:compileKotlinDesktop --no-daemon --max-workers=1 --console=plain: pass, BUILD SUCCESSFUL in 37s, 82 actionable tasks.
  - :composeApp:desktopTest --no-daemon --max-workers=1 --console=plain: pass, BUILD SUCCESSFUL in 7s, 55 actionable tasks.
- Clean detached validation worktree /home/brandon/worktrees/kite-revenge-validate-dbd57198 checked out at exact source commit a3426d2e4825679548e3282a87d22a6f18b7264b; Matrix Rust SDK remained pinned to 128049fd3b183f059fb76402c82ce56ba7ddcd37.
- :androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon --max-workers=1 --console=plain: pass, BUILD SUCCESSFUL in 1m 4s, 279 actionable tasks.
- Exact APK: /home/brandon/worktrees/kite-revenge-validate-dbd57198/androidApp/build/outputs/apk/PerfDebug/androidApp-PerfDebug.apk, 107,886,711 bytes, SHA-256 342134cf8c515e8b0a838d39b8bb1a8ca339b9febdbb70d59521238049d22680.
- AAPT verifies package app.kite.revenge.debug, label Kite, version perfdebug-26.10.14, target SDK 37 and native code arm64-v8a.
- APK signature verified with the existing V2 signer SHA-256 011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd.
- Samsung SM-S931B replacement install preserved debug state: dataDir remains /data/user/0/app.kite.revenge.debug, firstInstallTime remains 2026-10-14 11:55:12, and lastUpdateTime advanced to 2026-10-15 07:06:30.
- Post-install package filtering shows app.kite.revenge.debug; production app.kite was not installed/overwritten/cleared and the redundant app.kite.revenge package was not recreated.
- The phone was Dozing with NotificationShade focused at the final checkpoint. Kite and Google Messages were not launched after replacement installation, and no SMS/RCS or external Matrix action was sent for visual QA.
- No fresh 120 Hz frame-time claim is made. This slice changed non-scrolling preview/verification/transient surfaces and did not add per-row Matrix collectors or a parallel state system.
- Concurrent unrelated local changes appeared while this run was active (ComposerRow.kt, EventRowContextMenu.kt, InboxScreen.kt, InboxTopNavigation.kt, InboxViewModel.kt, AppStateStore.kt, ScSdkRoomSortOrder.kt and strings.xml). They remain unstaged and were excluded from this checkpoint.

### Next substantial slice
- When the Samsung is naturally awake and Kite can be foregrounded without disrupting the user, visually compare this exact installed build against the installed Google Messages app for invite/preview, verification, dark theme, long names/MXIDs, insets and transient notices; fix concrete mismatches in the same run.
- Continue the adjacent Google-Messages-style conversation interaction surfaces: composer attachment treatment, long-press/selection state, reactions/action sheets and remaining dialogs/transient states, preserving Kite's Matrix-specific controls.
- Capture controlled 120 Hz frame evidence on Inbox/Conversation scrolling and navigation before making a measurable performance-parity claim.


## 2026-10-15 — Inbox ordering and streamlined composer/message actions

### Implemented
- Removed the floating "Start chat" CTA from the native inbox while keeping Kite's preferred bottom search field fixed in place, and removed the unused top-navigation start-chat affordance. The start-chat destination itself is retained for other entry paths.
- Removed "Show more" from the message long-press context menu; previously nested actions are now available directly in the menu rather than being dropped, retaining Matrix-specific capabilities and contextual permissions.
- Applied equal 4 dp outer button padding to the composer leading attachment-plus and trailing gallery shortcuts for balanced icon-to-edge spacing while retaining 48 dp minimum click targets.
- Removed the room-list comparator's unconditional "invites first" rule, which could promote years-old room invites over current conversations. Existing opt-in favourite, low-priority and unread grouping settings remain unchanged, then newest `latestEventTimestamp` wins.
- Kept unrelated existing hide-chat work-in-progress edits in `InboxViewModel.kt`, `AppStateStore.kt` and strings untouched and excluded from this commit.

### Validation
- `:composeApp:compileAndroidMain :composeApp:compileKotlinDesktop :composeApp:desktopTest --quiet --no-daemon --max-workers=1` passed on Glass (return code 0).
- `:androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --quiet --no-daemon --max-workers=1` passed on Glass (return code 0).
- APK: `~/kite-revenge/androidApp/build/outputs/apk/PerfDebug/androidApp-PerfDebug.apk`; SHA-256 `4b25500f9e5214aaae16e44f07f9c89b601c80c3aa9bc81abaa51a78157eaf3c`, package `app.kite.revenge.debug`, signed with pre-existing debug signer SHA-256 `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd`.
- `adb install -r` on Samsung SM-S931B succeeded; `lastUpdateTime` 2026-10-15 07:15:24. First install remains 2026-10-14 11:55:12 and data directory remains `/data/user/0/app.kite.revenge.debug`. Production `app.kite` was not modified.
- No message send, no production account changes, no forced UI launch, and no visual/120 Hz benchmark claims. Runtime screen-level visual parity and actual multi-year-invite list ordering require an observational device check when convenient.


## 2026-10-15 — Chronological inbox with pinned-first ordering

### Report and diagnosis
- User reported Benny Jekel's old Facebook Messenger conversation appearing at the very top. Matrix history for room `!KGnkBZxsyGDBFXbrSQ:matrix.presley.nz` shows its last indexed message timestamp 1458589914555 (21 Mar 2016 UTC). An SDK-supplied room order was being forwarded unchanged whenever the inbox search field was blank; the earlier invitation comparator fix did not guarantee a correct normal inbox.
- User also reported pinned chats missing from first position. In native Kite, the existing row Pin action toggles Matrix `RoomInfo.isFavorite`; that field was not considered by the blank-search filter when we first added chronological ordering.

### Changes
- For blank search, exclude spaces, put `isFavorite`/pinned rooms at the top, and then order within pinned and unpinned groups by descending `RoomSummary.latestEventTimestamp`. Null timestamps are last and the configured session order resolves ties.
- Preserve search ranking by name-match position and recency. Preserve the existing Matrix room ID set, actions, and the pinned icon; no extra per-row collectors or new storage.
- Add desktop regression tests including an old Facebook chat passed first by the upstream SDK, null activity, space exclusion, equal timestamp session tie-break, and multiple pinned rooms.
- `InboxViewModel.kt` already contained ongoing unrelated hide-chat edits. Stage only the new `isPinned` lambda, not those edits.

### Validation
- Glass `:composeApp:desktopTest :composeApp:compileAndroidMain --no-daemon --max-workers=1 --quiet`: pass.
- Glass `:androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon --max-workers=1 --quiet`: pass.
- ARM64 APK `~/kite-revenge/androidApp/build/outputs/apk/PerfDebug/androidApp-PerfDebug.apk`, SHA-256 `6413a353527ad687f79ec0dc8d4093b2d621e25d197c35174ef198ee9a0b4d9f`, confirmed package `app.kite.revenge.debug`, existing signer SHA-256 `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd`.
- `adb -s <private-adb-device> install -r` returned Success; retained isolated debug app package and did not modify production `app.kite` or Matrix account data.
- Did not launch or interact with private live conversations; device-side direct order/visual proof remains to be collected. Rust's reported `latestEventTimestamp` can differ from indexed message history, so a live timestamp inspection is a follow-up if Benny still appears incorrectly without being pinned.


## 2026-10-15 — Leave-chat overlay and heart reaction animation

- Replaced layout-resizing bottom confirmation card with a Material 3 AlertDialog overlay. Confirm, cancel, and dismiss callbacks remain routed to the same existing handlers. Critical action gating is preserved; no chat was left during validation.
- Added Flutter Kite-inspired 540 ms pink-heart double-tap burst with sparkles, lift, scale and fade, plus haptic feedback. The visual is drawn by drawWithContent, without adding layout, shifting message bounds or consuming tap gestures. Only adding a reaction animates; removing one does not.
- Existing ReactionsRow can still change message height when a new reaction badge appears. No claim of perfect zero layout shift without direct screen measurements.
- Glass desktop tests and Android/desktop compilation succeeded after fixing a draw-transform pixel conversion scope error. Glass ARM64 PerfDebug APK build succeeded.
- Verified package app.kite.revenge.debug and existing signer. APK SHA-256 6e70d42e2c175619930662ff0eaa52d04180679f216ac53ce3ad3c2806c9501c. adb install -r on Samsung succeeded. Debug install time and dataDir persisted; production app.kite untouched.
- Live modal/gesture interaction not performed because ChatGPT was foreground on Samsung. Existing hide-chat work remains untouched.


## 2026-10-15 — Quiet attachment open and three-action message long-press menu

### Implemented
- The existing attachment tap handler already downloaded/reused the persistent cached file and launched Android's ACTION_VIEW via FileProvider. Suppressed the redundant "Attachment downloaded" success banner only on the DownloadFileAndOpen/tap path, so tapping simply opens it without a global bottom-app-message layout shift. Explicit Download/Save still confirms success; failures still surface. No storage, MIME or intent handling was changed.
- Simplified the message long-press context menu to the existing quick reactions row (five emojis plus add reaction), followed only by **Copy**, **Select** (or Deselect when selected), and **Delete**. Removed reply/edit/forward/info/download/thread/dev tools/other options from this menu, without removing their underlying keyboard actions, other navigation flows or selection toolbar.
- Copy still uses `Action.Event.CopyContent`; Delete still uses permission checks and the existing confirmation. Actions unavailable for the event are omitted. Quick-reaction toggle and selected state use the existing Matrix semantics.

### Validation
- Glass `:composeApp:compileAndroidMain :composeApp:compileKotlinDesktop :composeApp:desktopTest --no-daemon --max-workers=1 --quiet`: passed.
- Glass `:androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon --max-workers=1 --quiet`: passed.
- ARM64 APK SHA-256 `4b26d5f853704f91af6b15007b77cd755d5d2e7b1266b07f4f04cffc97fc82fe`, package `app.kite.revenge.debug`, existing certificate verified. Installed via `adb -s <private-adb-device> install -r` (Success). DataDir and firstInstallTime retained; lastUpdateTime `2026-10-15 07:59:50`. Production `app.kite` untouched.
- No live message interaction performed; visual behavior and actual open-intent result depend on the device's installed file handlers. Preserved unrelated in-progress hide-chat work in `InboxViewModel.kt`, `AppStateStore.kt`, and strings.


## 2026-10-15 — Keep Delete visible in message long-press menu

- User screenshot showed reaction row, Copy and Select, with Delete missing. Cause: `EventRowContextMenu` was dropping the entire Delete entry using `.takeIf { canRedact }` whenever the Rust SDK reported insufficient redaction permission, or the event identifier was absent.
- Delete is now always displayed after Copy and Select for a user message, with `enabled = canRedact`. Thus it stays visible (greyed out if not permitted), without bypassing Matrix access controls, confirmation or the underlying redaction action. Transaction IDs also count as valid identifiers for pending own sends.
- Added `MessageDeleteMenuTest` covering own/other permissions, missing event IDs, and null permission state.
- Glass checks: `:composeApp:compileAndroidMain :composeApp:compileKotlinDesktop :composeApp:desktopTest --no-daemon --max-workers=1 --quiet` passed; ARM64 `:androidApp:assemblePerfDebug` passed.
- Verified isolated Android APK package `app.kite.revenge.debug` and existing signer. `adb install -r` succeeded on Samsung; first install time and app data path unchanged, last update `2026-10-15 08:06:32`. Production `app.kite` not modified. No live chat or redaction action was performed; visual verification is pending.
- Existing unrelated unfinished hide-chat changes in InboxViewModel, AppStateStore and strings left unchanged.


## 2026-10-15 — Full-row tap selection in conversation selection mode

- User requested tapping anywhere on a message while selection mode is active to select or deselect it, rather than tapping only the selection circle. Existing row primary action was insufficient because child links/media/polls/reaction chips can receive and consume taps.
- Added a last-drawn transparent `Box` overlay with `matchParentSize().clickable(...)` over the full selectable event row **only** when selection is active. It uses the existing `toggleSelection` callback, announces Select/Deselect to accessibility, and has no ripple or layout measurement impact. The old row click/long-click handler is disabled during selection to avoid duplicate toggles; keyboard actions remain registered.
- The selection overlay covers attachments, message text, sender headers, avatar, timestamps, reaction chips, and the selection indicator. Nonselectable system rows are excluded; outside selection mode the overlay is absent and normal attachment/link/reaction/swipe handling is unchanged. Compose clickable cancels in favor of parent LazyColumn scrolling when the gesture is a drag.
- Glass validation: `:composeApp:compileAndroidMain :composeApp:compileKotlinDesktop :composeApp:desktopTest --no-daemon --max-workers=1 --quiet` passed after closing the inner Column correctly and removing an invalid `matchParentSize` import. `:androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a --no-daemon --max-workers=1 --quiet` passed.
- ARM64 APK SHA-256 `d0ae905f7684c8d92c735ec38e4aaf097c477832ceb6f5f6b48759a9cbc9227e`, package `app.kite.revenge.debug`, prior signer verified. Samsung `adb install -r` returned Success; dataDir `/data/user/0/app.kite.revenge.debug` and original install date retained, lastUpdateTime `2026-10-15 08:25:43`. Did not touch production `app.kite` or live Matrix state.
- No live tap test/visual proof; handset was running ChatGPT. Existing unrelated hide-chat work in InboxViewModel, AppStateStore and strings was kept untouched and excluded from commit.


## 2026-10-15 — Bury low-priority rooms below normal activity in Kite Revenge

- Fixed the personal inbox's local sorting layer (`filterKiteInboxItems`), which previously only considered favourites and latest event timestamps. Rooms marked `isLowPriority` now stay below normal rooms regardless of how recently they received a message; newest-first order is retained inside each group. Favourites remain first, including favourites that are themselves low priority, matching original Flutter Kite precedence without restoring its unconditional invite-first policy.
- Matrix Rust SDK sorting, unread handling, and persisted room tags are unchanged. Search results still sort by text match and recency, so low-priority rooms remain searchable.
- Added three Kotlin regression tests: low-priority activity cannot overtake normal rooms, explicit favourites still win, and low-priority search matches remain visible. Existing room-list tests also passed.
- On Glass: focused `:composeApp:desktopTest --tests chat.schildi.revenge.model.KiteInboxFilterTest` passed; `:composeApp:compileAndroidMain` passed; ARM64 `:androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a` passed.
- Verified APK package `app.kite.revenge.debug`, version code 1, existing signer SHA-256 `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd`. Installed in place via `adb -s <private-adb-device> install -r` (Success), last update 2026-10-15 14:59 NZDT; firstInstallTime remained 2026-10-14 11:55:12. No production app or Matrix account state reset. Live UI sorting not verified due to foreground handset use.
- Preserved unrelated in-progress local hide-chat edits in InboxViewModel.kt, AppStateStore.kt, and strings; do not include those in this commit.

## 2026-10-15 — Remove unwanted red jump-target stripe from Kite Revenge chats

- Removed `drawJumpTargetDecoration()` from conversation event rendering, including the red `MaterialTheme.colorScheme.error` line, the unused `JUMP_TARGET` highlight enum branch, and its derived state. Kept jump-to-message navigation, target resolution, and the separate action-target background highlight intact.
- Glass `:androidApp:assembleDebug -PandroidAbi=arm64-v8a --no-daemon` passed (188 tasks; 32 s). `git diff --check` passed.
- Built ARM64 debug APK SHA-256 `5bb49e2d1b4dcb975fda11f2e719d773bb6873a2c28986ef7645328eb8501d91`. Installed over `app.kite.revenge.debug` on Samsung SM-S931B with `adb install -r` (Success); original firstInstallTime `2026-10-14 11:55:12`, new lastUpdateTime `2026-10-15 16:34:10`, and data directory `/data/user/0/app.kite.revenge.debug` preserved. Production `app.kite` untouched.
- Live chat visual comparison was not performed. Preserved unrelated in-progress local inbox edits in InboxViewModel, AppStateStore, and strings.

## 2026-10-15 — One Kite Revenge package ID and Samsung release-install policy

- Standardized `androidApp/build.gradle.kts` to use `app.kite.revenge.debug` directly as `defaultConfig.applicationId` for every build type. Removed all `applicationIdSuffix` assignments, tightened the configuration guard, and configured optimized release builds to use the same existing signing certificate as Samsung's installed package. Earlier mentions of a second package ID elsewhere in this historical ledger record past configurations, not current build instructions.
- Updated `AGENTS.md` to require **installing successfully changed code on Samsung in release mode**, and updated `ANDROID.md` to show the single-ID release installation procedure.
- Glass: `:androidApp:assembleRelease -PandroidAbi=arm64-v8a --no-daemon` **BUILD SUCCESSFUL** (280 tasks, 1m 9s). Final release APK `androidApp/build/outputs/apk/release/androidApp-release.apk`: package `app.kite.revenge.debug`, versionCode `26101500`, versionName `26.10.15`, `arm64-v8a`, non-debuggable, signer SHA-256 `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd` (same existing key), APK SHA-256 `3d4992f5c0d007914ec1d6a0d436b795a4a59892d705cd1ffe7ea89ffd774c09`.
- Samsung SM-S931B via `adb -s <private-adb-device> install -r` returned **Success**. Device subsequently reports exactly one Kite Revenge package `app.kite.revenge.debug`, versionCode `26101500`, `lastUpdateTime=2026-10-15 16:40:23`, preserved `firstInstallTime=2026-10-14 11:55:12` and `dataDir=/data/user/0/app.kite.revenge.debug`. Original Kite project and unrelated pending inbox changes untouched. No intrusive live chat UI test performed.

## 2026-10-15 22:49 NZDT — sending, unread and inbox ordering

- Reserve a stable, invisible timestamp/status footprint for own messages so local sending → sent does not reflow the message bubble.
- When the newest event in a live room is visibly at the bottom, mark the room read via SDK and clear any explicit unread flag; honour the configured auto-read trigger, including Never/Room close.
- Honor PIN_FAVORITES when sorting the Kite inbox; previously old favourited rooms were promoted despite the preference being off. Keep the separate low-priority grouping. Regression case added for pinning disabled.
- Glass: `:composeApp:desktopTest :androidApp:assembleRelease -PandroidAbi=arm64-v8a --no-daemon --max-workers=1` successful (1m 19s); `git diff --check` clean.
- Release APK package `app.kite.revenge.debug`, versionCode `26101500`, V2 signing SHA-256 `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd`, matches previously verified Samsung signer. ADB install -r on Samsung returned Success, firstInstallTime remained `2026-10-14 11:55:12`, lastUpdateTime became `2026-10-15 22:49:13`, dataDir preserved.
- The unread race has not yet been manually reproduced on the device; actual bridge backfill origin-timestamp behaviour also remains unverified.
- Preserved separate pre-existing unstaged hide-room edits in InboxViewModel, AppStateStore, and strings.xml; only the pin-order correction hunk of InboxViewModel staged.

## 2026-10-15 23:16 NZDT — send-state identity and bottom anchoring follow-up

- Fixed reversed conversation LazyColumn keying. Use the Rust timeline item `uniqueId` for both local echoes and sent events instead of switching from transaction ID to event ID. The Matrix Rust SDK explicitly documents `TimelineUniqueId` as preserved on updates (`matrix-rust-sdk/crates/matrix-sdk-ui/src/timeline/item.rs`). This avoids full row disposal/re-measure on send-state transition.
- Removed the half-screen negative scroll offset for `EventJumpTarget.Index(0)`, which was applied when aiming for the newest messages. Added bottom-follow when a new event arrives, but disable it once the user intentionally scrolls back. Explicit focused-event navigation remains unchanged.
- Restored Kite's pinned-first inbox ordering independently of the unrelated SDK `PIN_FAVORITES` preference; adjusted regression expectations. Historic bridge backfill timestamps remain a separate known root cause for older chats ranking too recently, not fixed by reordering alone.
- Glass validation: `:composeApp:desktopTest :androidApp:assembleRelease -PandroidAbi=arm64-v8a --no-daemon --max-workers=1` PASS (`BUILD SUCCESSFUL in 1m 17s`); `git diff --check` PASS.
- Verified APK package `app.kite.revenge.debug`, versionCode `26101500`, release signer SHA-256 `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd`. Samsung `adb install -r` PASS, firstInstallTime remained `2026-10-14 11:55:12`, lastUpdateTime `2026-10-15 23:16:11`. Data preserved.
- Live sending/scroll gestures not executed on the user's active phone; only build and desktop regression tests pass. Unrelated unfinished hide-room changes remain unstaged.

## 2026-10-16 — Send action inside the message field

- Moved the existing send/clear action from outside the composer pill into its trailing Row, keeping the 48 dp circular send target, send validation and disabled in-progress state. Removed the extra outside gap and obsolete sending placeholder; text stays in its own weighted slot.
- Glass `:composeApp:desktopTest :androidApp:assembleRelease -PandroidAbi=arm64-v8a --no-daemon --max-workers=1` passed. Release APK SHA-256 `d9ca7fdfa68ef5601a83d3fd9840777fd8c7256903355dbae252cb1c6233cf39`; package `app.kite.revenge.debug`, v26101600, release signer `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd` confirmed.
- Samsung `adb install -r` succeeded; firstInstallTime remained `2026-10-14 11:55:12`, dataDir remained `/data/user/0/app.kite.revenge.debug`, lastUpdateTime `2026-10-16 16:34:05`. Production Kite unaffected. Visual chat interaction not exercised to avoid disrupting the active phone session. Other in-progress inbox/notification changes left untouched.

## 2026-10-16 — Single Android task and retained inbox scroll

- The mobile UI already uses one MainActivity for ordinary navigation; multiple Recents windows came from `FLAG_ACTIVITY_MULTIPLE_TASK` in AndroidWindowManager and notification launches lacking explicit reuse. MainActivity now uses `singleTask`, all Android new-window routes use `CLEAR_TOP|SINGLE_TOP` (and `NEW_TASK` only from an application context), and notification launch intents also use `CLEAR_TOP`. OAuthCallbackActivity remains a transient no-display callback.
- Inbox scroll offset now belongs to the persistent `WindowContent` via one `rememberLazyListState`, provided to nested inbox screens. This is necessary because the default compact `InboxConversationMultiPaneScreen` removes its inbox pane from composition while a chat is open. Search results retain independent scroll state. No background room-list composables are kept alive.
- Glass `:composeApp:compileAndroidMain` PASS, `:androidApp:assembleRelease -PandroidAbi=arm64-v8a --no-build-cache` PASS (1m 3s), `git diff --check` PASS. Release APK package is `app.kite.revenge.debug`, existing and new release APK signing certificate SHA-256 both `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd`. Installed to Samsung S25 with `adb install -r` SUCCESS, preserving app data.
- Samsung functional proof: two Android notification-style main launch intents delivered the second to the existing top-most MainActivity, with one Kite Revenge task reported by ActivityManager. Reproduced scroll-position reset on the first two attempts; after moving the retained list state above the adaptive layout, scrolled list kept the same visible row and offset (Lachie/Brynley) after opening Brynley and pressing Android Back. Actual tap on a live notification was not performed to avoid altering unread messages.
- Preserved concurrent unrelated dirty inbox-model/store/strings changes and unrelated deleted packaging scripts.

## 2026-10-16 — Remove blank chat-open interval without speculative prefetch

- Root cause: while `ConversationViewModel.timelineItems` was initially null, ConversationScreen rendered `SplashScreenContent`; `rememberTransientLoadingVisible` intentionally painted nothing for 650 ms. The default conversation-details split also created a throwaway multi-pane destination on compact phones before rendering the actual chat.
- During normal joined-room timeline startup, render `ConversationTopNavigation(hasTimeline=false)` immediately and use a local 100 ms loading-grace override (the original global 650 ms grace remains for other screens). Skip the intermediate conversation-details split below the configured split-width threshold; larger windows preserve split-pane behavior.
- Evaluated eagerly starting raw/formatted timeline flows, but **reverted** it after noisy Samsung frame-time samples; the final code retains its original lazy/off-UI thread timeline formatting. No room prefetch, new persistent timeline cache, retained hidden screen, or new animations.
- Glass `:composeApp:desktopTest :androidApp:assembleRelease -PandroidAbi=arm64-v8a --no-daemon --max-workers=1 --no-build-cache` PASS and `git diff --check` PASS. Release APK package `app.kite.revenge.debug`, signer SHA-256 `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd`; Samsung update `adb install -r` SUCCESS with data preserved; did not launch/steal foreground after final install.
- Frame-time A/B inconclusive: short initial on-device probes had highly variable 50–80 frame samples, and a later baseline comparison was invalidated when another app took foreground. Therefore no measured frame-time improvement claim; the change conservatively minimizes added work and eliminates the known blank delay in code. Interactive validation of final exact build should be repeated only when Samsung is idle.
- Left unrelated dirty InboxViewModel/AppStateStore/strings.xml changes untouched.

## 2026-10-16 — Cold-start inbox blank frame shown in 14667.mp4

- Video: after OS splash, Kite shows a mostly white inbox shell from about 1.2s to 2.25s while rooms load, but subsequent chat transitions are relatively quick. This is the inbox's `roomsState == null` path using EmptyListScreen -> SplashScreenContent, which delays loading chrome for 650 ms.
- Render eight fixed, 80 dp, non-interactive skeleton rows during the null-room-state interval instead of a blank surface. Avatar size and row height match real inbox rows; use no animations/shimmer, network prefetch, extra subscriptions, or hidden conversation components. Preserve genuine empty/search states, scroll anchor, and existing SDK flow behavior.
- Glass `:composeApp:desktopTest :androidApp:assembleRelease -PandroidAbi=arm64-v8a --no-daemon --max-workers=1 --no-build-cache` PASS; `git diff --check` PASS. Android release `app.kite.revenge.debug` signed with existing cert SHA-256 `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd`; Samsung `adb install -r` SUCCESS (no uninstall/data reset). Foreground was NotificationShade, so did not launch the app for video comparison; rendering measurement remains unverified on final build.
- Leave unrelated active InboxViewModel/AppStateStore/strings.xml edits unstaged.

## 2026-10-17 — Settings back navigation and repository location

- Active native Kotlin/Compose repository moved from `~/kite-revenge` to `~/kite` on Glass; Git worktree links repaired. The legacy Flutter repository remains read-only at `~/.archived/kite`. Older paths recorded above are historical.
- Settings screen now intercepts Android Back even at the root. Detail pane Back returns to settings root; subsequent Back navigates to inbox rather than delegating to activity exit.
- `SettingsBackNavigationTest` (two regression tests): PASS with `:composeApp:desktopTest --tests chat.schildi.revenge.SettingsBackNavigationTest` (JDK 25); Android ARM64 `:androidApp:assemblePerfDebug -PandroidAbi=arm64-v8a` PASS. Not yet tested interactively on Samsung; no installation or account state modified.

## 2026-10-17 — Fix profile/settings toolbar Back exiting Android app

- The root cause was `TopNavigationCloseOrNavigateToInboxIcon`: on Android it offered `closeScreen` (which finishes the activity) instead of inbox navigation because the single-window branch was inverted.
- For Android, normal settings/account toolbar Back now navigates to the inbox; initial account setup retains its special case. Desktop multi-window behavior unchanged.
- Three `TopNavigationBackTest` regressions PASS; Android signed ARM64 release `:androidApp:assembleRelease -PandroidAbi=arm64-v8a` PASS. Installed on Samsung Galaxy S25 with `app.kite` app data preserved; device lock prevented live UI navigation verification.

## 2026-10-18 — Single-tap timestamps, compact message menu, Android Ogg audio

- A short single tap on a normal message bubble now toggles the full local sent date and time beneath it; the passive pointer observer preserves immediate double-tap reactions and long-press/selection. The detector is disabled during selection or an open message-action menu.
- Compact long-press menu reduces action-item height and spacing, removes the layered panel treatment, transparent backing and extra shadow/tonal elevation; all quick reactions, Copy/Select/Delete permissions remain unchanged.
- Samsung reports only Termux as an `audio/ogg` ACTION_VIEW handler. Android Kite now handles audio attachments in-app with a minimal native MediaPlayer screen (play/pause, seek, progress, lifecycle release). Matrix `.ogg`/`.oga`/`.opus` filenames supply audio MIME when senders mark them generic, and original filenames reach the player.
- Verification: `:composeApp:compileKotlinDesktop :androidApp:assembleDebug` PASS on Glass with JDK 25 and Gradle offline; `git diff --check` PASS. Initial package attempt hit a stale pre-rename dex cache path; `:composeApp:clean` resolved it. The debug APK declares `app.kite` and that package already exists on Samsung, so it was **not installed**; real-device tap/menu/audio playback and frame-time verification remain outstanding.

## 2026-10-18 — Configurable time display

- Added Settings → General → Time format (default 12-hour AM/PM), with 24-hour, 12-hour with seconds, and 24-hour with seconds choices. Preference uses the existing persistent settings store.
- A single theme-level Compose preference read supplies the chosen format to inbox time, conversation swipe and status timestamps, message info, threaded replies, user activity, verification details and tap-to-reveal full date/time. Formatting honors local timezone; changing the preference refreshes visible times without per-row preference collectors.
- `:composeApp:desktopTest --tests chat.schildi.revenge.TimeFormatTest :composeApp:compileAndroidMain` PASS, including default, midnight/noon, all four selections and full date/time. Android ARM64 release version 26.10.18.1 (26101801) built from commit 13aaa822 and signed with the existing Kite key; Samsung `adb install -r` SUCCESS, original first-install timestamp and `/data/user/0/app.kite` preserved. Interactive UI validation remains pending.

## 2026-10-18 — Remove embedded audio player; use external mpv

- Deleted the Android `AudioPlaybackActivity` and its manifest declaration. Android audio attachments again use `ACTION_VIEW` with temporary `FileProvider` read grants, so a compatible external player can open them.
- Kept MIME inference for `.ogg`, `.oga`, and `.opus` filenames mislabeled as binary, along with unrelated single-tap timestamps and compact context-menu changes.
- Confirmed Samsung S25 has F-Droid-signed mpv-android `is.xyz.mpv`, version `2026-09-17-release` (48), installed; Android resolves mpv for `content:` `audio/ogg` VIEW intents.
- Release verification: clean detached worktree build `:androidApp:assembleRelease -PandroidAbi=arm64-v8a -PandroidVersionCode=26101802 -PandroidVersionName=26.10.18.2` PASS; APK `app.kite` arm64 signer SHA-256 matches installed `app.kite`; `adb install -r` on Samsung Galaxy S25 PASS with app data retained; `dumpsys package` confirms version `26.10.18.2`. In-app tap of a real Matrix audio attachment has not yet been tested.

## 2026-10-18 — Selected reaction contrast

- Selected (self-reacted) reaction chips now use an opaque Material 3 `primaryContainer` fill, `primary` outline and `onPrimaryContainer` count text instead of a translucent accent overlay. Unselected chips remain unchanged.
- Verified `:composeApp:compileAndroidMain --offline` PASS and `git diff --check` PASS on Glass. Visual inspection of the updated APK on Samsung remains pending.

## 2026-10-18 — Sent time in long-press menu and local profile photos

- Moved full sent date/time from single-tap inline expansion to a compact, non-action label in the existing message long-press menu. Swipe-to-reveal time and configured time formats remain intact.
- Tapping the avatar on User Details opens the existing photo picker. Own-account photos attempt a Matrix avatar upload; other users, or failed own uploads, receive persistent per-session/per-user local overrides. Updated photo rendering across chat, DM headers/inbox, member lists, receipts, polls and account avatars, with local removal from User Details.
- Glass proof: `:androidApp:compileDebugSources :androidApp:verifyKiteLongPressMenu --offline --no-daemon` PASS with JDK 25 and Android SDK; `git diff --check` PASS. Not yet installed on Samsung or visually validated with a logged-in account; no real Matrix upload or picker interaction tested.

## 2026-10-18 — Keep sent timestamps exclusively inside message long-press popup

- Removed the remaining sent-time text from message bubble status decorations, hidden swipe overlays, system/state event rows, and threaded-reply previews. A message's full sent time remains available only within its long-press actions popup. Sending/error/edited indicators remain on the bubble.
- Removed timestamp reveal from swipe settings and gesture implementation. Legacy persisted timestamp-swipe settings are safely treated as None; swipe-to-reply remains available. Shrunk the reserved delivery-status width to match icons without text.
- Glass verification: Android/desktop source compilation, targeted `MessageSwipeActionsTest` and `StableTextMessageLayoutTest`, and `verifyKiteLongPressMenu` all PASS; `git diff --check` PASS. Device UI check pending.

### Release install verification — 2026-10-18

- Built isolated committed source `9d914dec` in existing clean detached worktree `/home/brandon/worktrees/kite-release-625be7bb`; initial build failed due to stale incremental Kotlin lookup storage, retry with `-Pkotlin.incremental=false` succeeded.
- Arm64 release APK: `app.kite`, `26.10.18.3` (`26101803`), signed with SHA-256 `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd`; identical to the installed Samsung signing certificate as verified by pulling its previous APK and checking both with `apksigner`.
- `adb install -r` on Samsung S25 (10.66.66.3:5555) returned Success. `dumpsys package app.kite` confirms `26.10.18.3`, firstInstallTime unchanged (`2026-10-16 18:00:56`). Screen was locked when inspected, so long-press popup visual interaction remains unverified; phone was not unlocked or reset.

## 2026-10-18 — Sent timestamp footer in long-press menu

- Move full sent date/time below every context-menu action in the message popup, with 8dp vertical padding. No timestamp is rendered inline in the conversation.
- Verify release source and packaging in isolated clean worktree, then install `app.kite` on Samsung via `adb install -r` while retaining its existing version code and Matrix app data.
- Verified on Glass from clean detached worktree at `254142d5`: `:androidApp:assembleRelease :androidApp:verifyKiteLongPressMenu -PandroidAbi=arm64-v8a -Pkotlin.incremental=false` PASS (1m24s); APK `app.kite`, signed with existing certificate, versionCode `26101803` unchanged. New release APK SHA-256 `123de838b00bab484a560a0534d89586fee7d30f012d8e39ba59ba74c4989ff6`. `adb install -r` on Samsung S25 returned Success and original firstInstallTime retained. Device popup interaction not exercised.

## 2026-10-18 — Timestamp at top of message popup

- Moved the full sent date/time to the **first row** of the long-press message popup, above the reaction shortcut row and message action entries. Kept timestamps entirely off chat rows and retained existing timestamp text and versionCode.
- User-profile image editing: verified that UserDetailsScreen already supports tap-avatar to pick a photo, local-per-session/per-user overrides persist using LocalAvatarOverrides and are used by AvatarImage in chats; own avatar also attempts SDK upload. Added explicit **Change photo** button wired to the same picker action as the avatar tap for discoverability. Real-device interactive picker remains unverified while the Samsung is locked.
- Isolated release worktree `452c0899`: `:androidApp:assembleRelease :androidApp:verifyKiteLongPressMenu -PandroidAbi=arm64-v8a -PandroidVersionCode=26101803 -PandroidVersionName=26.10.18.3 -Pkotlin.incremental=false` PASS. Signed release APK (`app.kite`, same cert, unchanged versionCode), SHA-256 `6a2dc8b6009bda908a05373e83eadaad452540f378c58f02566275ba1bea4b83`, installed on Galaxy S25 `adb install -r`: Success; firstInstallTime unchanged. The device screen was locked for UI inspection; interaction not tested.

## 2026-10-18 — Compact date popup and composer spacing

- Gave the message long-press date its own content-width rounded surface above the reaction/action panel. The message dropdown background is transparent behind the separate surfaces; ordinary menus stay unchanged.
- Cut last-message bottom spacer from 16dp to 4dp. The multiline composer retains 12dp vertical text padding with a 56dp minimum row height.
- Glass verification: `:androidApp:compileDebugSources :androidApp:verifyKiteLongPressMenu --offline --no-daemon -Pkotlin.incremental=false` PASS. Isolated arm64 release APK from `ded151ae` produced, ZIP and APK signature verified (SHA-256 `928b68c5070fbdc4ac9489c582cdf78c1d898c7f90268786b7f47b04df5fd982`), installed via `adb install -r` on Samsung S25 (Success); `app.kite`/`26101803` and original firstInstallTime retained. Real-device popup interaction not verified.

## 2026-10-18 — Neutral message Delete action

- Removed the message long-press Delete entry's critical/red styling; text and icon now use the same default colour as Copy/Select. Deletion permissions and behaviour are unchanged.
- Isolated release build at `fd1cf786`: `:androidApp:assembleRelease :androidApp:verifyKiteLongPressMenu` PASS. APK SHA-256 `48a8c2c6b968d70c8f2d459ef6cc18a03cae6c1811fa65a6a6b9b7a7ead18139`. Verified package `app.kite`, unchanged versionCode `26101803`, existing signing certificate. Installed on Samsung S25 with `adb install -r` (Success); original firstInstallTime preserved. Interactive visual check not performed.

## 2026-10-18 — Borderless, stable-size image messages

- Image-only messages and stickers no longer paint an outgoing/incoming bubble behind the picture. The image's aspect-ratio-constrained outer component owns the message bounds, so portrait screenshots do not sit centered in wide coloured bubbles.
- Reserve the same width/height from Matrix metadata for blurhash/loading/error and decoded media; content fills those bounds without changing the measured row size on decode. Captions and replies retain their normal bubble background.
- Glass verification: `:composeApp:compileAndroidMain` PASS (28s), isolated `:androidApp:assembleRelease -PandroidAbi=arm64-v8a` PASS (5m), `git diff --check` PASS. APK SHA-256 `3e0ff360dcf3940dc1f1f5782fcf93f44a70d9b77e809700a0972c9075ae1cae`; package `app.kite`, signing certificate unchanged, versionCode `26101803` unchanged. `adb install -r` on Samsung S25: Success; firstInstallTime unchanged (`2026-10-16 18:00:56`). Visual/layout-jank test not performed; missing Matrix dimensions still use stable square fallback.

## 2026-10-18 — Full-height images and no media status pill

- Removed the normal-image 500dp maximum height; an image with Matrix width/height metadata now reserves its full displayed aspect ratio at available message width, before or after Coil decode. Reply thumbnails retain their compact maximum height; unknown dimensions retain the fixed square fallback, with no decode-triggered list remeasurement.
- Image-only transparent bubbles no longer request a grey status-overlay background; existing sending/failed indicators remain possible without that pill. Captions and replies retain their normal styling.
- Glass verification: isolated arm64 `:androidApp:assembleRelease` through buildq job 5 PASS (4m56s; lint PASS). APK SHA-256 `eedad99b268bf14c6821a124c2f454a41e1530b9c796350bd9bacc9277de7507`; `app.kite`, original signing certificate and versionCode `26101803`. `adb install -r` on Samsung S25 PASS; firstInstallTime `2026-10-16 18:00:56` unchanged. Visual and scroll-jank measurements still unverified on unlocked device.

## 2026-10-18 — Room-open stability, media captions and reactions

- Loading chat now reserves the 56dp composer before the timeline appears. Default Index(0) opening no longer re-keys the list when it is already at position 0, avoiding a needless anchor reset.
- Captioned images render text above the image, with the image filling the same message width. Its aspect ratio remains derived from metadata before decoding; image-only messages remain unchanged.
- Message long-press date, reaction shortcuts, and Copy/Select/Delete actions now use separate rounded surfaces. Actions are 192dp wide instead of inheriting the wide emoji row.
- Replaced the broken full reaction chooser's composer REACTION mode with a searchable emoji grid that dispatches ToggleReactionKey directly.
- Glass: `:androidApp:compileDebugSources :androidApp:verifyKiteLongPressMenu` via buildq #47 PASS; `git diff --check` PASS. Device visual testing and frame-time proof still pending (Samsung locked).

## 2026-10-19 — Messenger-like media captions and stable reaction rows

- Captioned portrait images now use a compact 220dp maximum width (other captioned images 320dp), keeping the attached image and its text above it within one right/left-aligned bubble. Image-only messages retain their original sizing. The caption no longer updates media status layout state after text measurement.
- Reaction chips are overlaid within the event content bounds instead of entering or leaving the measured event column; adding/removing a reaction no longer changes row height.
- Glass: `:composeApp:compileAndroidMain` PASS via buildq #257; `:androidApp:assembleRelease -PandroidAbi=arm64-v8a -PandroidVersionCode=26101901 -PandroidVersionName=26.10.19.1` PASS via buildq #259. APK package `app.kite` and signing SHA-256 `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd` match the installed Samsung package. Samsung S25 `adb install -r` PASS for `app.kite` version `26.10.19.1` (`26101901`); existing firstInstallTime (`2026-10-16 18:00:56`) preserved. Direct visual validation of the image/caption and reaction gestures is pending.

## 2026-10-19 — Restore reaction position and reduce reaction flicker

- Restored reaction chips to their original dedicated row beneath message content; the previous overlay overlapped text.
- Smoothed genuine reaction-row height changes with `animateContentSize`; retain last nonempty reaction chips for 180ms across transient empty Matrix reaction updates, avoiding an empty/reappearing row during server confirmation.
- Removed transient `Processing` app messages from both keyboard/action-menu reaction toggle paths (`ToggleReactionKey` and `ToggleReactionIndex`), retaining error notification on failure. Direct chip toggles continue to use the existing asynchronous action.
- Glass: `:composeApp:compileAndroidMain` passed through buildq #264; signed arm64 release `:androidApp:assembleRelease` passed through buildq #266. APK package is `app.kite`, version `26.10.19.2` (`26101902`), signer SHA-256 `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd` matches the installed app. `adb install -r` on Samsung S25 returned Success, original `firstInstallTime` `2026-10-16 18:00:56` unchanged. A real in-room reaction UI/frame-time test remains unverified: the S25 was in another app and Waydroid has no Kite installation/session.

## 2026-10-19 — Remove global transient message widget

- Removed Kite's `AppMessages` bottom panel, including clipboard success notices and status/error banners that resized the chat viewport; ignored generic `AppMessage` instances at publication. Clipboard operations still copy content without in-app feedback. Retained confirmation prompts and device-verification requests as explicit dialogs (including verification failure feedback). Removed unused clipboard-status strings.
- Validation: `git diff --check` PASS; Glass buildq #325 `:composeApp:compileAndroidMain` PASS; buildq #330 `:composeApp:compileKotlinDesktop` PASS; buildq #331 `:composeApp:compileKotlinDesktop :composeApp:compileAndroidMain` PASS after the final edit. No Samsung install or device UI verification performed; unrelated Kotlin warnings remain.

## 2026-10-19 — Transient message release installed on Samsung

- Reconciled the `fix/kite-no-transient-messages-20261019` changes into main via commit `12cb4cb2`, preserving the unrelated in-progress inbox-hiding modifications untouched in the main worktree. Built from the independent clean branch whose Git tree matches main `12cb4cb2` exactly.
- Glass buildq #344: `:androidApp:assembleRelease -PandroidAbi=arm64-v8a -PandroidVersionCode=26101903 -PandroidVersionName=26.10.19.3` PASS (280 tasks). APK SHA-256: `74058c0d9106f0e4e0314b34b57878a9aebdfc247ceade49704ece333ad5ad42`; package `app.kite`, code `26101903`, signer certificate SHA-256 `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd`.
- Samsung S25 (`10.66.66.3:5555`): pulled installed release APK before updating, verified signer fingerprint exactly matches new release, ran `adb install -r` successfully, verified installed code `26101903`, unchanged signing identity, unchanged `firstInstallTime` and user-data inode. Launched `app.kite/chat.schildi.revenge.MainActivity` with `Status: ok` (cold start 270 ms), verified process alive, no fatal exception in sampled logcat. Clipboard and the absent text widget were not manually exercised in UI. No uninstall or data reset.

## 2026-10-19 — Fix heart burst clipping on short messages

- Root cause: the double-tap heart was drawn inside message content nested under `animateContentSize`, which clips it on short text bubbles. Split the passive double-tap listener from its drawing layer; convert tap coordinates to event-row coordinates and draw the identical 540 ms heart/sparkles over the outer row, outside the animated-size clip, without changing measured row height or reaction chip placement. Non-consuming touch handling and reaction toggling are unchanged.
- Glass buildq #389: `:composeApp:compileKotlinDesktop :composeApp:compileAndroidMain` PASS (78 tasks). `git diff --check` PASS. UI clip rendering and Samsung release verification pending.

## 2026-10-19 — Heart burst fix installed on Samsung

- Release build on Glass using buildq task #390: `:androidApp:assembleRelease -PandroidAbi=arm64-v8a -PandroidVersionCode=26101904 -PandroidVersionName=26.10.19.4`, PASS. APK SHA-256 `bdf04d6197eb248a9ea93282719a21e4594909b91a12dd20b29cb7423ffe0670`; package `app.kite`, signature SHA-256 `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd` matches existing installation.
- Samsung SM-S931B in-place update `adb install -r`: Success. Device confirms version code `26101904`, version name `26.10.19.4`, unchanged `firstInstallTime` and app-data inode, startup `Status: ok` and process alive; no fatal crash markers in sampled logcat. The actual on-screen burst clipping was **not** visually retested: user resumed another foreground app. No data reset/uninstall. Main's unrelated inbox WIP preserved.

## 2026-10-19 — Heart animation: eliminate lazy-row clipping

- Follow-up recording showed the previous event-row drawing layer still clipped at the edge of short LazyColumn items. Moved the existing 540 ms heart/sparkle draw into the conversation viewport Box, outside the LazyColumn. A shared stable CompositionLocal passes a viewport coordinate callback to message tap handling, retaining existing gesture and reaction actions. The overlay does not change any item measurements, reaction chip positions, or touch targets.
- Glass buildq #416 `:composeApp:compileKotlinDesktop :composeApp:compileAndroidMain` PASS. In-device visual retest pending release install.

## 2026-10-19 — Samsung release 26.10.19.5 with viewport heart overlay

- Glass buildq #417: signed `:androidApp:assembleRelease -PandroidAbi=arm64-v8a -PandroidVersionCode=26101905 -PandroidVersionName=26.10.19.5` PASS. Artifact SHA-256 `ddcb32fd248ea9aaa0be8f230faf6d8ee13174365bf6e46c84f028d969286c03`; application ID `app.kite`; signer certificate SHA-256 `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd`, unchanged from installed release.
- Installed via `adb install -r` on Samsung Galaxy S25 `10.66.66.3:5555`: Success. Android reports `26.10.19.5`, code `26101905`, unchanged signing identity, `firstInstallTime` and app-data inode. `am start -W` PASS (cold start 274 ms), app process running, no sampled FATAL exception.
- On-device double-tap burst rendering has not been visually re-tested yet. The phone had returned to the user’s ChatGPT conversation when UI inspection was attempted; did not interact with the user’s chat/reactions. Main’s separate inbox changes remain unmodified.

## 2026-10-21 — Remove inbox search-results heading

- Removed the conditional “Conversations” heading/list item when filtering the inbox. Search results now begin directly with matching rooms; room ordering and Kite’s bottom-anchored search field are unchanged. Removed the unused resource/import.
- Validation: `git diff --check` PASS; Glass buildq #559 `:composeApp:compileAndroidMain` PASS. No Samsung visual check or release installation performed.

## 2026-10-21 — Kite 1.0.3 Samsung release install

- Built clean commit `6a4b5a7f` (inbox search-results heading removed) from `/home/brandon/worktrees/kite-hide-search-header-20261021`. Glass buildq #561 `:androidApp:assembleRelease -PandroidAbi=arm64-v8a -PandroidVersionCode=101000003 -PandroidVersionName=1.0.3` PASS (280 tasks).
- Verified release APK package `app.kite`, version `1.0.3` / `101000003`, signing SHA-256 `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd`, matching the previously installed 1.0.2 APK.
- Samsung Galaxy S25 (`10.66.66.3:5555`): `adb install -r` Success; package version advanced from 1.0.2/101000002 to 1.0.3/101000003 and original `firstInstallTime=2026-10-16 18:00:56` persisted. Cold start `am start -W` Status ok (244ms); process running. Search heading was not visually checked on device.

## 2026-10-21 — Bridge one-to-one notification titles

- Samsung `dumpsys notification --noredact` for the reported Tyla Lockwood · Facebook notification showed exactly one MessagingStyle message, but `android.isGroupConversation=true` with the same `android.title` and `android.conversationTitle`, explaining the double sender/title display.
- Notification grouping now uses DM/direct flags and the single-sender/room-name match for bridge pseudo-DMs; genuine group rooms or histories with multiple senders retain group presentation. Suppresses the redundant one-to-one conversation title and sender prefix, and aligns shortcut person with that classification.
- Glass buildq #572 `:composeApp:desktopTest :composeApp:compileAndroidMain` PASS, including 3 new notification grouping tests (0 failures). `git diff --check` PASS. Actual next inbound Samsung notification remains unverified.

- Glass buildq #574 `:androidApp:assembleRelease -PandroidAbi=arm64-v8a -PandroidVersionCode=101000004 -PandroidVersionName=1.0.4` PASS. Verified package `app.kite`, version 1.0.4 and signer SHA-256 `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd` matches installed releases.
- Samsung SM-S931B `adb install -r` Success; `dumpsys package` confirms version code 101000004, app data retained (`firstInstallTime=2026-10-16 18:00:56`). Existing notifications are from the previous build; only a subsequent actual incoming notification can verify the rendered UI.

## 2026-10-20 — Nox/GitHub release integration history

## 2026-10-20 — Inbox, notification, reaction and timeline feedback

- Opening message notifications now routes to the live room and dismisses every active notification for the same session and room. Normal room openings no longer focus an old fully-read marker; explicit unread jumps are unchanged.
- Inbox subtitles contain message content without a duplicate sender prefix. Emoji-only bubbles have a tighter trailing inset.
- Reaction deselection updates immediately and reconciles with Matrix state, with a timeout rollback; double-tap burst animates the chosen emoji with heart/face/thumb-specific movement and stays above the composer edge.
- Verification: `:composeApp:compileAndroidMain` succeeded through Nox buildq task 355; `git diff --check` clean. Signed release and real Samsung interaction verification pending.

## 2026-10-20 — Reaction exit motion and burst layering

- Animate immediate reaction-chip removal with a 180 ms fade/shrink; retain SDK-removed chips for 220 ms so quick acknowledgements cannot interrupt the exit.
- Give active double-tap bursts max z-order on both message content and their timeline row until animation completes.
- Nox `buildq` job 375: `:androidApp:assembleRelease -PandroidAbi=arm64-v8a` PASS. The APK is **unsigned** because canonical Kite release-signing environment is unavailable on Nox; Samsung install and on-device animation verification remain pending.

## 2026-10-20 — Odin hardware proof: reaction exit without FlowRow jolt

- Corrected the regression from `ecb95f6`: `shrinkHorizontally` modified reaction-chip width every frame, forcing `FlowRow` to reposition its neighbours. Chip exit now fades at fixed measured width; when its last reaction is removed, the entire reactions row uses a 240 ms vertical collapse.
- Samsung Galaxy S25 hardware test on the **Odin** Matrix conversation (not other chats): double-tapped the existing short own message to add ❤️, then tapped that reaction to remove it. Confirmed the reaction disappeared. Captured the real device screen recording at `/home/brandon/.cache/kite-release/odin-reaction-26102003.mp4` (47 encoded video frames, 1080×2340). In the exit frames, the same message bubble at x≈974 moved smoothly from y=1700 to y=1788; largest successive-frame displacement was 8 px, with no instantaneous layout jump. No new text message was sent.
- Nox `buildq` #389 `:androidApp:assembleRelease` PASS (arm64-v8a). Signed local APK with the existing Kite certificate SHA-256 `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd`; Samsung `adb install -r` succeeded and installed `app.kite` version `26.10.20.3` (versionCode 26102003) preserving data.
- This proves the specific final-chip reaction-removal motion on Odin; broader combinations of simultaneous reactions and top-layer bursts were not rerun in this capture.

## 2026-10-20 — Suppress reaction action progress notification

- Reproduced in user-provided Odin recording `14776.mp4`: a transient `Processing` app message flashes below the composer during a double-tap heart reaction.
- Root cause: `Action.Event.ToggleReactionKey` and `ToggleReactionIndex` requested `notifyProcessing = true` in `ConversationViewModel`, causing `ActionContext.launchActionAsync` to publish the `action_processing` message despite successful asynchronous reaction toggles.
- Removed this flag for both reaction actions, leaving error reporting in `launchActionAsync` unchanged; direct chip toggling already uses the silent `toggleReaction` path.
- Nox `buildq` job #402 `:androidApp:assembleRelease -PandroidAbi=arm64-v8a -PandroidVersionCode=26102004 -PandroidVersionName=26.10.20.4` passed. Signed APK with canonical certificate `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd`; Samsung Galaxy S25 `adb install -r` returned `Success`, installed version 26102004, preserved original firstInstallTime.
- **Not visually verified after installation**: Odin interaction retest blocked by Samsung's secure lock screen (Window focus `Bouncer`). Do not describe this as hardware UI proof.

## 2026-10-20 — Message long-press menu order and spacing

- Place Select/Deselect above Copy; leave Delete last. Quick reactions and timestamp layout remain unchanged.
- Remove the cramped 40dp fixed rows: Copy/Select/Delete now use 48dp height with 4dp top and bottom in their grouped surface, matching the rhythm of the existing quick-reaction row.
- Nox `buildq` job #404 `:androidApp:assembleRelease -PandroidAbi=arm64-v8a -PandroidVersionCode=26102005 -PandroidVersionName=26.10.20.5` PASS. Signed the 26.10.20.5 APK with the verified existing Kite certificate; `adb install -r` returned Success on Samsung Galaxy S25; `firstInstallTime` unchanged.
- Device visual menu check remains outstanding: Samsung was at its locked screen when inspection was attempted. Do not claim the spacing was visually validated on hardware.

## 2026-10-21 — Reconcile Glass and GitHub/Nox histories after stale release regression

- Nox `/home/brandon/worktrees/kite-notification-name-20261020` and current GitHub `main` contained original duplicate-name fix `8326605` (Kite 1.0.2). Glass release 1.0.3 was built from a diverged local `main` that omitted eight GitHub-only commits, including the fix; this explains the observed 1.0.3 regression.
- Merged both branch histories with distinct selection/reaction layout improvements kept, and retained viewport-owned reaction rendering while supporting non-heart emoji bursts. Kept the notification single-contact logic plus older dismissal/message-opening fixes. Added release source ancestry requirement to AGENTS.md.
- Glass buildq #584 `:composeApp:desktopTest :composeApp:compileAndroidMain` PASS; includes notification grouping regression tests. Device/UI integration and 1.0.5 release installation not yet performed.

## 2026-10-21 — Reconciled Kite 1.0.5 installed on Samsung

- Verified `git merge-base --is-ancestor origin/main HEAD`, with both Nox `8326605` and Glass `990bf0a9` original/renewed duplicate-name notification fixes included in merge `ac7a72fa`; GitHub main pushed at that commit.
- Glass buildq #585 signed `:androidApp:assembleRelease -PandroidAbi=arm64-v8a -PandroidVersionCode=101000005 -PandroidVersionName=1.0.5` PASS (280 tasks, 5m 51s). APK `app.kite`, SHA-256 signer `011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd` matches the installed release signer.
- Samsung SM-S931B (`10.66.66.3:5555`) `adb install -r`: Success. Version 1.0.5 / 101000005 confirmed; `firstInstallTime=2026-10-16 18:00:56` unchanged, app data retained. Fresh inbound notification visual proof still pending.

## 2026-10-21 — Matching rounded corners on sent images

- Moved media clipping from the Coil subcomposed image to its enclosing measured media viewport. Outgoing and incoming images, stickers, and video thumbnails now share the bubble-derived rounded shape without adding an image background or changing reserved dimensions.
- Glass isolated worktree: `:composeApp:compileAndroidMain --offline --no-daemon -Pkotlin.incremental=false` PASS via buildq #604 (3m 36s); `git diff --check` PASS. Samsung visual comparison is pending.
