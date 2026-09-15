# Kite Roadmap

Kite is a Flutter Matrix client whose target is **Element X feature parity, Element X-level visual polish, and measurably better interaction stability**.

Parity is a moving target. The reference is the current `develop` branch of Element X Android, re-audited before completing every milestone. This roadmap was established on **2026-09-14**.

## Non-negotiable product contracts

These rules apply to every milestone and cannot be traded away to ship a feature faster.

- [x] Use Signals for app state. Do not introduce Riverpod.
- [x] Do not introduce `go_router`; keep navigation explicit and lightweight.
- [x] Keep the deterministic 200-room / 100-message benchmark fixture.
- [x] Keep the zero-jitter contract pinned in `PERFORMANCE.md` and `PerformanceContract`.
- [x] Keep the benchmark negative control: the 40 ms injected stall must fail the same benchmark that clean Kite passes.
- [x] Keep the deterministic 120 Hz geometry/motion contract.
- [ ] Every new primary interaction gets a deterministic motion test and a profile-mode frame benchmark before its milestone is complete.
- [ ] Every roadmap checkbox that changes UI or runtime behaviour must pass `tool/quality_gate.sh` before it is marked complete.
- [ ] Physical-device release candidates must additionally pass the Android Macrobenchmark with zero build, raster, and end-to-end frame-budget violations.
- [ ] Never implement Matrix cryptography ourselves. Use audited Matrix SDK primitives.
- [ ] Offline-first rendering: cached UI renders immediately; network/sync work must never blank an already-known screen.
- [ ] No visible loading-induced layout shift. Skeletons/placeholders reserve final geometry.
- [ ] No broad reactive rebuilds when a leaf signal can express the dependency.
- [ ] No blocking disk, crypto, image decode, JSON parsing, database migration, or Matrix sync work on the Flutter UI isolate.

## Definition of Element X parity

A feature is only considered parity-complete when all of the following are true:

- Behaviour matches the current Element X Android user flow for normal, loading, empty, error, offline, permission-denied, and destructive-action states.
- The feature interoperates correctly with other Matrix clients and encrypted rooms.
- The feature survives app restart and offline/online transitions where Element X does.
- Notifications/deep links return to the correct state.
- Accessibility semantics, focus, keyboard navigation, large text, RTL, and screen-reader behaviour are covered where applicable.
- The screen has approved light and dark reference screenshots and passes Flutter golden tests.
- Motion is deliberate and stable; no accidental position, size, opacity, or scroll jumps occur.
- The interaction's benchmark passes the pinned performance contract.

## Visual-quality contract: as beautiful as Element X

Kite should not merely contain the same controls. It must have the same level of composition, restraint, consistency, and finish.

- [x] Build a Kite design-token layer for typography, spacing, radii, elevation, stroke widths, opacity, semantic colours, animation durations, and easing.
- [ ] Audit Element X's Compound-based visual hierarchy screen-by-screen and reproduce the same quality level with Kite branding.
- [ ] Match Element X's uncluttered information density: strong primary hierarchy, quiet secondary metadata, obvious selected/unread/mention states, and no gratuitous chrome.
- [ ] Reproduce the polished avatar treatment and contextual colour/bloom concept without copying Element trademarks/assets.
- [ ] Use high-quality avatars and media at their actual rendered resolution; never upscale tiny thumbnails into visible blur.
- [ ] Keep touch targets at least platform-accessible size while preserving compact visual rhythm.
- [ ] Light, dark, and true-black themes with correct system-bar treatment.
- [ ] Consistent sheets, dialogs, menus, snackbars, tooltips, empty states, error states, and destructive confirmations.
- [ ] Deliberate motion system: room changes, new messages, reactions, sheets, navigation, image viewer, composer expansion, and call transitions use consistent curves and durations.
- [x] Respect reduced-motion accessibility settings.
- [x] Build a Flutter golden-gallery equivalent to Element X's screenshot gallery.
- [ ] Every reusable component has golden coverage in light/dark and representative edge states.
- [x] Every top-level screen has phone portrait, phone landscape, tablet, and desktop-width reference renders where layout differs.
- [x] Golden diffs are a merge gate; visual changes require an explicitly approved golden update.
- [x] Maintain a manual side-by-side review checklist against current Element X reference screenshots for every major UI milestone.

## Milestone 0 — Foundation and reproducible quality gates

- [x] Flutter project scaffold.
- [x] Signals 7 state management.
- [x] Riverpod removed.
- [x] `go_router` removed.
- [x] Deterministic chat benchmark fixture.
- [x] Profile-mode `FrameTiming` benchmark for opening a DM.
- [x] Waydroid positive-control benchmark passes.
- [x] Artificial-jitter negative control fails with one cold and 30/30 warm build-budget violations.
- [x] Clean rerun passes after negative control.
- [x] Android Macrobenchmark module compiles.
- [x] Pinned `PerformanceContract` and independent pin test.
- [x] Repository quality-gate script.
- [x] Establish golden-test infrastructure and approved first baseline images.
- [x] Add deterministic clocks, IDs, image fixtures, permission adapters, connectivity adapters, and fake Matrix event streams for all integration tests.
- [x] Add structured logging and trace IDs for sync, timeline, media, encryption, notification, and call flows.
- [x] Define crash/error reporting abstraction with no secrets or decrypted message contents in diagnostics.

**Exit:** the app cannot accidentally weaken its performance contract, every test fixture is reproducible, and visual diffs can be reviewed mechanically.

## Milestone 1 — Matrix engine, storage, sync, and lifecycle

- [ ] Integrate the Matrix Rust SDK through a minimal Dart/Flutter boundary, or document a demonstrably equivalent SDK choice before implementation.
- [x] Homeserver discovery and `.well-known` handling.
- [ ] Simplified Sliding Sync / current Matrix SDK sync path with fast initial room-list population.
- [ ] Incremental sync without full-screen refreshes.
- [ ] Encrypted persistent SDK stores.
- [x] Local presentation cache designed for immediate room-list/timeline rendering.
- [ ] Back-pagination and automatic pagination near timeline edges.
- [x] Correct deduplication and ordering of sync events.
- [x] Offline send queue and deterministic retry states.
- [x] Connectivity loss/recovery without room-list or timeline jumps.
- [x] Background/foreground lifecycle handling.
- [x] Process-death restoration to the previous account and sensible navigation state.
- [x] Deep-link routing for room, event, user, invite, and call links.
- [ ] Multiple accounts if present in current Element X baseline, with isolated stores and notification routing.

**Verification note (2026-09-15):** the Matrix Rust SDK boundary, encrypted SDK store, resumable incremental `/sync`, narrow presentation updates, lifecycle/recovery wiring, and automatic back-pagination are implemented with passing focused tests. Native cold-start sync now sorts room deltas off the UI isolate, publishes large initial room populations in bounded room chunks, and withholds the resumable cursor until the final chunk so interrupted/process-death recovery cannot skip unseen rooms; resumed sync remains unchunked and immediately uses the full timeline depth. Cache restore, incremental sync completion, pagination completion, cached account/navigation activation, and account/navigation deactivation publish related Signals atomically, while leaf-only room metadata changes preserve room-order identity. Sync/pagination FFI and JSON decoding remain behind background-isolate adapters, retry backoff is bounded and deterministic, presentation/restoration files recover the last complete state across interrupted replacements or a corrupt primary with a valid backup, sync bursts coalesce bounded presentation snapshots, truncated presentation snapshots deliberately drop their resume cursor so omitted rooms are repopulated after process death, active-account removal clears navigation/restoration atomically, lifecycle transitions invalidate stale pagination completions, and account teardown cancels runtime sync before closing the SDK boundary and clears abandoned presentation writes. Crash reports retain only structural Dart/package stack frames, and synchronous or failing presentation adapters are contained as recoverable sync state. Current producer verification passes Flutter analysis, all 374 deterministic tests with 3 intentional native-library skips, the real native ABI suite with 10 tests, and Rust formatting/tests/build verification (6 tests). Runtime-backed boxes remain unchecked because the required locked Waydroid baseline still fails the 16,666 µs raster contract before the negative-control phase: this branch reached 45,027 µs cold-open raster, 20,061 µs warm-open raster, 21,847 µs send raster, 90,003 µs reply raster, 41,849 µs copy raster, 46,532 µs delete-confirmation raster, 25,692 µs delete-redaction raster, and 21,504 µs edit raster. A separately locked run from current `main` reproduced the same repository-wide pattern, including 43,506 µs cold-open and 86,992 µs reply raster. Thresholds were not weakened, and the current SDK path remains a work branch until the repository-wide performance contract passes.

**Benchmarks:** cold app open, warm app open, account switch, sync update into room list, room pagination, offline-to-online recovery.

## Milestone 2 — Authentication, session verification, encryption, and app lock

- [ ] Homeserver selection and discovery UI.
- [ ] Password login where supported.
- [ ] OIDC/native authentication flow.
- [ ] SSO/web authentication fallback where required.
- [ ] QR sign-in/device-to-device login where supported upstream.
- [ ] Account registration flow where supported by the homeserver.
- [ ] Session restore and soft-logout handling.
- [ ] Mandatory device verification flow equivalent to Element X.
- [ ] QR verification.
- [ ] Emoji/SAS verification.
- [ ] Cross-signing trust state.
- [ ] Encrypted backup creation, restore, recovery-key/passphrase flows, and recovery status.
- [ ] Historical encrypted-message recovery.
- [ ] Unverified-device/user warnings and recovery UX.
- [ ] Encryption state and trust indicators in room/details flows.
- [ ] Encrypted history sharing on invite when supported by room/server policy.
- [ ] PIN app lock.
- [ ] Biometric unlock.
- [ ] Hide notification contents while Kite is locked.
- [ ] Session/device list, current-device identification, verification state, and remote sign-out.

**Exit:** a user can install Kite on a clean device, securely sign in, verify it, recover encrypted history, lock the app, and manage sessions without needing Element X.

## Milestone 3 — Home, room list, filters, Sections, invites, and Spaces

- [ ] Element X-quality home header/profile treatment.
- [ ] Fast room list with stable scroll position during sync.
- [ ] Correct latest-event previews and sender attribution.
- [ ] Unread counts.
- [ ] Mention indicators.
- [ ] Activity indicators for muted-notification rooms.
- [ ] Active-call decoration.
- [ ] Muted-room decoration.
- [ ] Favourite state.
- [ ] Room-list filters equivalent to current Element X: All, Unreads, People/DMs, Rooms, Favourites, plus current upstream additions.
- [ ] Current Element X Sections organisation behaviour where enabled upstream.
- [ ] Read-all action.
- [ ] Invite cards and accept/decline flows.
- [ ] Create DM from people search.
- [ ] Create a room while inviting someone when no suitable DM exists.
- [ ] Room directory discovery/search supported by current Element X.
- [ ] Public/private/knock room discovery and join/request flows as supported upstream.
- [ ] Joined Spaces visible from the home experience.
- [ ] Space filter row with zero room-list reflow jitter.
- [ ] Dedicated Spaces area.
- [ ] Space invitation preview with inviter, description, member context, and external/internal treatment where available.
- [ ] Browse/discover rooms in a Space, including rooms not yet joined.
- [ ] Create Space.
- [ ] Edit/manage Space.
- [ ] Add/remove/link rooms in Spaces.
- [ ] Choose a Space during room creation or create a spaceless room.
- [ ] Nested Space navigation if present in current upstream baseline.

**Benchmarks:** launch-to-room-list, filter change, Space change, invite accept, room creation, returning from a room without scroll movement.

## Milestone 4 — Timeline rendering and message state

- [ ] Virtualised timeline capable of very large histories without retaining every rendered widget.
- [ ] Stable scroll anchoring when events arrive above/below the viewport.
- [ ] Stable scroll anchoring during back-pagination.
- [ ] Text messages.
- [ ] Rich formatted messages.
- [ ] Links and link previews where Element X supports them.
- [ ] Inline code and fenced code blocks.
- [ ] Quotes.
- [ ] Mentions with correct visual treatment.
- [ ] Replies with reply preview and jump-to-event.
- [ ] Edited-event indication and edit history behaviour matching upstream.
- [ ] Redacted/deleted event rendering, including collapsed runs where upstream does so.
- [ ] Reactions with summary and reactor detail.
- [ ] Images.
- [ ] Videos and playable video previews.
- [ ] Files.
- [ ] Audio.
- [ ] Voice messages.
- [ ] MIDI/audio types currently supported upstream.
- [ ] Static location events.
- [ ] Live-location timeline state.
- [ ] Poll events and animated/result states.
- [ ] Call-started/active/ended/declined timeline events.
- [ ] Membership/profile/state events with the same filtering rules as Element X.
- [ ] Own-message sending/sent/read/failure states.
- [ ] Typing indicators.
- [ ] Read receipts and receipt-details UI.
- [ ] Read marker.
- [ ] Jump/scroll to unread.
- [ ] Event permalink/deep-link focus.
- [ ] RTL message detection and rendering.
- [ ] Date separators and timestamp rules.

**Jitter contract:** incoming messages, read receipts, typing indicators, send-state changes, reaction updates, pagination, and media completion must not move unrelated visible events.

## Milestone 5 — Composer, rich text, sending, and message actions

- [ ] Element X-quality composer geometry and visual states.
- [ ] Rich-text editor by default.
- [ ] Markdown composer mode/advanced setting if still offered upstream.
- [ ] Bold, italic, underline/strike where supported, inline code, code block, quote, lists, links, and other current rich-text actions.
- [ ] Full-screen rich-text editing.
- [ ] Mention autocomplete for users/rooms as supported.
- [ ] Reply composer state.
- [ ] Edit existing messages.
- [ ] Delete/redact messages with confirmation semantics matching upstream.
- [ ] Emoji picker.
- [ ] Reactions from quick action and full picker.
- [ ] Copy text.
- [ ] Share message/content through platform share sheet.
- [ ] Forward a message to one or multiple rooms.
- [ ] Report message/content where available.
- [ ] Attach files.
- [ ] Pick images/videos.
- [ ] Capture media from camera.
- [ ] Media preview before send.
- [ ] Image crop and rotate before send.
- [ ] Captions on media.
- [ ] Voice-message record, cancel, preview, send, playback state.
- [ ] Static location picker/share.
- [ ] Live location start/stop/status and permission handling.
- [ ] Create/respond/end polls.
- [ ] Sending progress, retry, cancel where supported, and deterministic failure UI.

**Benchmarks:** keyboard appearance, composer expansion, formatting toolbar, media picker return, send message, react, edit, reply, attachment preview.

## Milestone 6 — Threads 2.x parity

- [ ] Render thread summaries in the main timeline.
- [ ] Open thread without disturbing main-timeline scroll position.
- [ ] Read and write thread replies.
- [ ] Thread composer/reply state.
- [ ] Thread pagination.
- [ ] Thread read receipts/unread state.
- [ ] Thread notifications/subscriptions as supported by current Element X.
- [ ] Thread unread state correctly decorates the parent room and relevant filters.
- [ ] Jump from notification/activity to the correct threaded event.
- [ ] Media playback and message focus remain scoped correctly when entering/leaving threads.
- [ ] Prevent unsupported actions such as live-location sharing in threads when upstream does.

**Exit:** a heavy Threads user can use Kite without losing unread discoverability or context.

## Milestone 7 — Media viewer and content workflows

- [ ] Full-screen image viewer with smooth hero transition and no source-thumbnail flash.
- [ ] Video viewer/playback.
- [ ] Swipe/browse adjacent timeline media where upstream supports it.
- [ ] Load full-resolution media only for the visible item.
- [ ] Formatted media captions.
- [ ] Download/save media.
- [ ] Share media internally and through the OS.
- [ ] Avatar full-screen preview.
- [ ] Media/file/link gallery tabs where present upstream.
- [ ] Content scanner/warning flow if part of current Element X public baseline.
- [ ] Correct encrypted-media caching and cleanup.

## Milestone 8 — 1:1 and group voice/video calling

- [ ] MatrixRTC/Element Call integration matching current Element X semantics.
- [ ] Start 1:1 voice call.
- [ ] Start 1:1 video call.
- [ ] Start/join group call.
- [ ] Incoming-call notification and ringing UI.
- [ ] Accept/decline/hang up.
- [ ] Microphone mute.
- [ ] Camera enable/disable and camera switch.
- [ ] Audio-route selection.
- [ ] Participant grid/spotlight behaviour appropriate to Element Call.
- [ ] Picture-in-picture.
- [ ] Continue calls with app backgrounded/phone locked where platform permits.
- [ ] OS audio focus and interruption handling.
- [ ] Reconnect after transient network loss.
- [ ] Call timeline events and active-call state.
- [ ] Custom call ringtone setting.
- [ ] Deep links into calls.
- [ ] E2EE call identity/trust handling supplied by the Matrix/Element Call stack.

**Benchmarks:** incoming-call screen, accept-to-media, in-call controls, PiP transition, return from PiP, hang-up back to room.

## Milestone 9 — Room creation, room details, membership, and moderation

- [ ] Create DM.
- [ ] Create private room.
- [ ] Create public room where server policy allows.
- [ ] Knock/restricted join-rule flows supported by current upstream.
- [ ] Name/topic/avatar editing.
- [ ] Canonical alias/address handling where exposed upstream.
- [ ] Encryption choice/policy with safe defaults.
- [ ] History visibility/history sharing controls exposed upstream.
- [ ] Room notification override.
- [x] Member list and search.
- [x] Member profile bottom sheet/details.
- [x] Invite members.
- [x] Roles/power levels.
- [x] Promote/demote where authorised.
- [x] Kick.
- [x] Ban/unban.
- [ ] Report user/room where supported.
- [ ] Leave room.
- [ ] Forget/remove local room state where relevant.
- [ ] Convert/use DM semantics correctly when SDK room metadata changes.

## Milestone 10 — User profile, settings, notifications, privacy, and account management

- [ ] View own profile.
- [ ] Edit display name and avatar.
- [ ] View another user's profile/avatar.
- [ ] Start/open DM from user profile.
- [ ] Ignore/block controls supported upstream.
- [ ] Account management and sign out.
- [ ] Multi-account management if present upstream.
- [x] General settings.
- [x] Light/dark/system/black appearance modes matching current upstream capabilities.
- [x] Language selection.
- [x] Notification master settings.
- [x] Per-room notification settings.
- [x] Mentions/calls/message notification categories.
- [x] Custom message notification sound.
- [x] Custom call ringtone.
- [ ] Push registration and encrypted notification payload handling.
- [ ] Badge counts and clear-on-read behaviour.
- [ ] Privacy/security settings.
- [ ] Session/device management.
- [ ] App lock settings.
- [x] Cache/storage management without destroying diagnostic logs unexpectedly.
- [x] Report-a-problem flow with sanitised logs.
- [x] About/version/licenses.
- [ ] Developer settings only where they are genuinely useful; never leak Matrix complexity into normal settings.

## Milestone 11 — Notifications and deep-link correctness

- [ ] FCM-compatible push path where applicable.
- [ ] Non-Google/background sync notification path where required for distribution targets.
- [ ] Message notifications.
- [ ] Mention notifications.
- [ ] Invite notifications.
- [ ] Thread notifications.
- [ ] Call notifications with full-screen/incoming-call semantics where platform allows.
- [x] Grouping and summary notifications.
- [x] Notification privacy when app locked.
- [x] Tapping a notification lands on the exact room/event/thread/call.
- [x] Reading in Kite clears the corresponding notification promptly.
- [x] Reading elsewhere reconciles stale notifications.
- [ ] Account-aware notification routing for multi-account support.

## Milestone 12 — Accessibility, localisation, and adaptive layouts

- [ ] TalkBack semantics for every actionable element.
- [ ] Logical screen-reader timeline order.
- [ ] Focus indicators and keyboard traversal.
- [ ] Large font/text scaling without clipping or hidden actions.
- [ ] Minimum contrast compliance in every theme/state.
- [ ] RTL layout and event-text correctness.
- [x] Reduced motion.
- [ ] Colour is never the sole carrier of unread/error/selection state.
- [x] Accessible media labels and call controls.
- [x] Localisation framework and plural handling.
- [ ] Date/time/number formatting by locale.
- [ ] Phone portrait/landscape layouts.
- [ ] Foldable/tablet layout.
- [ ] Desktop-width Flutter layout that preserves the Element X visual language rather than simply stretching phone UI.
- [ ] Mouse hover, right-click/context menus, keyboard shortcuts, and resizable panes on desktop.

## Milestone 13 — Visual parity audit and polish pass

This milestone is not optional cleanup; it is a product feature.

- [ ] Capture the current Element X Android reference gallery and current Kite gallery for the same representative states.
- [ ] Home/room list side-by-side review.
- [ ] DM timeline review.
- [ ] Group-room timeline review.
- [ ] Composer/rich-text review.
- [x] Message action/reaction review.
- [x] Threads review.
- [ ] Spaces review.
- [ ] Room creation/invite review.
- [ ] Room/user details review.
- [ ] Settings/security review.
- [ ] Poll/location/media review.
- [ ] Incoming/outgoing/in-call review.
- [ ] Empty/loading/error/offline states review.
- [ ] Light/dark/black themes review.
- [ ] Typography hierarchy review.
- [ ] Spacing/radius/icon-size consistency review.
- [ ] Avatar/image quality review.
- [ ] Motion/easing review at normal speed and frame-by-frame.
- [ ] Remove all temporary Material defaults that do not match the intended Kite design language.
- [ ] Remove debug-looking labels, placeholder copy, generic scaffold visuals, and inconsistent icons.
- [ ] User-test the core flows for clarity without explaining Matrix concepts.

**Exit:** screenshots should look intentionally designed next to Element X, not like a Flutter approximation of it.

## Milestone 14 — Full parity audit against current Element X `develop`

- [x] Re-scan current upstream feature modules, release notes, screenshots, and Labs flags.
- [x] Build a screen-by-screen parity matrix with `Element X behaviour`, `Kite behaviour`, `test`, and `status` columns.
- [ ] Run through every Element X settings entry and verify Kite has the corresponding capability or a documented intentional difference.
- [ ] Run through every Element X room-list action.
- [ ] Run through every Element X timeline event type.
- [ ] Run through every Element X message action.
- [ ] Run through every Element X room/user moderation action.
- [ ] Run through every Element X notification/deep-link route.
- [ ] Run through every Element X call flow.
- [ ] Run through every Element X Space/Thread flow.
- [x] Confirm upstream features introduced after this roadmap date have been added or explicitly scheduled.
- [x] Confirm known upstream-missing features are not incorrectly called parity blockers simply because Matrix Classic has them.

## Milestone 15 — Release-grade performance and reliability

- [ ] Expand the zero-jitter harness from `open_dm` to every primary navigation and mutation journey.
- [x] Room-list scroll benchmark with thousands of rooms.
- [x] Timeline scroll benchmark with mixed rich event types.
- [x] Pagination benchmark.
- [x] New-message insertion benchmark.
- [x] Reaction/read-receipt/typing-update benchmark.
- [x] Composer + keyboard benchmark.
- [x] Search/filter benchmark.
- [x] Spaces/Sections benchmark.
- [ ] Thread open/switch benchmark.
- [ ] Media viewer benchmark.
- [x] Call-screen transition benchmark.
- [ ] App startup benchmark.
- [x] Offline recovery benchmark.
- [ ] Memory-growth soak test while switching rooms and paginating.
- [x] Image/media cache pressure test.
- [x] Repeated login/logout/account-switch store-cleanup test.
- [ ] Thermal/low-memory/background-kill testing on physical Android hardware.
- [ ] Physical Android Macrobenchmark matrix on at least one 60 Hz and one 120 Hz device.
- [ ] No accepted performance regression without before/after evidence and an explicit product decision.

## Milestone 16 — Release readiness

- [ ] Security review of SDK boundary, tokens, local stores, logs, media files, deep links, and exported Android components.
- [x] Dependency/license review.
- [ ] Reproducible signed Android release build.
- [ ] Linux/desktop release build if included in the first public target.
- [ ] Upgrade/migration tests between app versions.
- [x] Clean-install tests.
- [ ] Backup/recovery disaster tests.
- [ ] Notification tests across reboot/doze/background restrictions.
- [ ] Store metadata, privacy disclosures, licenses, and support/reporting links.
- [ ] Final `tool/quality_gate.sh` PASS.
- [ ] Final physical-device Macrobenchmark PASS.
- [ ] Final golden suite PASS.
- [ ] Final current-upstream parity audit PASS.

## Explicitly not a current parity blocker unless Element X ships it

The parity baseline is Element X, not every historical Element Classic capability or every open feature request. As of the roadmap audit, examples such as in-room message search and proposed on-device voice transcription have active/recent upstream requests and should not silently expand the parity definition until they actually land upstream. Re-audit these during Milestone 14.

## Upstream/reference sources

- Element X Android repository/develop: https://github.com/element-hq/element-x-android
- Element X Android releases: https://github.com/element-hq/element-x-android/releases
- Element X screenshot gallery: https://element-hq.github.io/element-x-android/
- Element X screenshot-testing approach: https://github.com/element-hq/element-x-android-neutrino/blob/develop/docs/screenshot_testing.md
- Element X Spaces launch, 2026-03-30: https://element.io/blog/spaces-has-landed-on-element-x/
- Element X/Pro roadmap context and Threads/Spaces direction: https://element.io/blog/element-x-and-pro-updates-a-glimpse-into-the-future/
- Element X design/performance philosophy: https://element.io/blog/element-x-experience-the-future-of-element/
- Element X production-ready/Element Call context: https://element.io/blog/we-have-lift-off-element-x-call-and-server-suite-are-ready/
- Element X rich text, polls, location, security and design history: https://element.io/blog/element-x-ignition/

## Roadmap maintenance rule

When Element X gains a new generally available user-facing feature, add it to the relevant Kite milestone during the next parity audit. Do not remove an existing Kite capability merely because upstream temporarily regresses it. Kite's target is **Element X parity or better, with stricter measurable smoothness**.
