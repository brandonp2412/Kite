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
- [x] Never implement Matrix cryptography ourselves. Use audited Matrix SDK primitives.
- [ ] Offline-first rendering: cached UI renders immediately; network/sync work must never blank an already-known screen.
- [ ] No visible loading-induced layout shift. Skeletons/placeholders reserve final geometry.
- [ ] No broad reactive rebuilds when a leaf signal can express the dependency.
- [x] No blocking disk, crypto, image decode, JSON parsing, database migration, or Matrix sync work on the Flutter UI isolate.

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
- [ ] Feature parity means capability parity, not exposing every feature at once. The home screen stays primarily a prominent search surface plus the chat list; secondary capabilities belong in contextual menus, sheets, or secondary screens rather than permanent dashboard chrome.
- [ ] Do not add persistent filter bars, chip rows, cards, status blocks, action strips, or other homepage furniture merely to satisfy roadmap checkboxes. A feature can be complete without occupying permanent home-screen space.
- [ ] Treat the current simplified Kite UI as the baseline. Do not mechanically copy Element X's chrome or resurrect removed clutter; match its restraint, hierarchy, and polish while keeping Kite simpler where that preserves discoverability.
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
- [x] Back-pagination and automatic pagination near timeline edges.
- [x] Correct deduplication and ordering of sync events.
- [x] Offline send queue and deterministic retry states.
- [x] Connectivity loss/recovery without room-list or timeline jumps.
- [x] Background/foreground lifecycle handling.
- [x] Process-death restoration to the previous account and sensible navigation state.
- [x] Deep-link routing for room, event, user, invite, and call links.
- [ ] Multiple accounts if present in current Element X baseline, with isolated stores and notification routing.

**Verification note (2026-09-16):** the Matrix Rust SDK boundary, encrypted SDK store, resumable incremental `/sync`, narrow presentation updates, lifecycle/recovery wiring, and automatic back-pagination are implemented with passing focused tests. Native cold-start sync now sorts room deltas off the UI isolate, publishes large initial room populations in bounded room chunks, and withholds the resumable cursor until the final chunk so interrupted/process-death recovery cannot skip unseen rooms; resumed sync remains unchunked and immediately uses the full timeline depth. Cache restore, incremental sync completion, pagination completion, cached account/navigation activation, and account/navigation deactivation publish related Signals atomically, while leaf-only room metadata changes preserve room-order identity. Sync/pagination FFI and JSON decoding remain behind background-isolate adapters, retry backoff is bounded and deterministic, presentation/restoration files recover the last complete state across interrupted replacements or a corrupt primary with a valid backup, sync bursts coalesce bounded presentation snapshots, truncated presentation snapshots deliberately drop their resume cursor so omitted rooms are repopulated after process death, active-account removal clears navigation/restoration atomically, lifecycle transitions invalidate stale pagination completions, and account teardown cancels runtime sync before closing the SDK boundary and clears abandoned presentation writes. Failed first-time account activation now releases transient runtime/store registrations without deleting the persisted presentation cache, failed account-switch persistence/startup rolls account and navigation back atomically, and a transient failure while stopping the prior account best-effort restores that account's sync while discarding the unopened target runtime. Crash reports retain only structural Dart/package stack frames, and synchronous or failing presentation adapters are contained as recoverable sync state. Current producer verification passes all 835 Flutter tests with 3 intentional native-library skips plus scoped Flutter analysis; the previously verified native ABI suite has 10 passing tests and Rust formatting/tests/build verification has 6 passing tests. Runtime-backed boxes remain unchecked because the required locked Waydroid baseline still fails the 16,666 µs raster contract before the negative-control phase: this branch reached 45,027 µs cold-open raster, 20,061 µs warm-open raster, 21,847 µs send raster, 90,003 µs reply raster, 41,849 µs copy raster, 46,532 µs delete-confirmation raster, 25,692 µs delete-redaction raster, and 21,504 µs edit raster. A separately locked run from current `main` reproduced the same repository-wide pattern, including 43,506 µs cold-open and 86,992 µs reply raster. Thresholds were not weakened, and the current SDK path remains a work branch until the repository-wide performance contract passes.

**Benchmarks:** cold app open, warm app open, account switch, sync update into room list, room pagination, offline-to-online recovery.

**Latest lane-1 verification (2026-09-16):** encrypted-store key lifecycle hardening passes 53 focused tests with clean scoped analysis, and the full Flutter suite exits successfully. No runtime-backed checkbox is newly complete; the locked Waydroid raster blocker below still applies.

**Cold-start empty-state progress (2026-09-18):** an authenticated account with no restored rooms now keeps the room-list geometry mounted with an explicit loading indicator until the first production sync batch arrives, rather than prematurely showing “No chats found”. Empty persisted snapshots deliberately discard any resume cursor before sync starts, preventing a stale cursor from preserving an empty presentation cache after restart. Focused cache/account/home tests pass.

## Milestone 2 — Authentication, session verification, encryption, and app lock

- [x] Homeserver selection and discovery UI.
- [x] Password login where supported.
- [ ] OIDC/native authentication flow.
- [ ] SSO/web authentication fallback where required.
- [ ] QR sign-in/device-to-device login where supported upstream.
- [ ] Account registration flow where supported by the homeserver.
- [x] Session restore and soft-logout handling.
- [ ] Mandatory device verification flow equivalent to Element X.
- [ ] QR verification.
- [ ] Emoji/SAS verification.
- [ ] Cross-signing trust state.
  - Progress 2026-09-23: production trust lookup is wired through the Rust Matrix SDK, runtime, and account boundary with regression coverage. Kept open because the required Waydroid profile gate currently fails its pre-existing 16.666 ms raster baseline.
- [ ] Encrypted backup creation, restore, recovery-key/passphrase flows, and recovery status.
- [ ] Historical encrypted-message recovery.
- [ ] Unverified-device/user warnings and recovery UX.
- [ ] Encryption state and trust indicators in room/details flows.
  - Progress 2026-09-23: production room encryption state and verified-device trust now come from the Rust Matrix SDK and feed the existing room/details trust UI. Kept open because the required Waydroid profile gate currently fails its pre-existing 16.666 ms raster baseline.
- [ ] Encrypted history sharing on invite when supported by room/server policy.
- [ ] PIN app lock.
- [ ] Biometric unlock.
- [ ] Hide notification contents while Kite is locked.
- [ ] Session/device list, current-device identification, verification state, and remote sign-out.

**Exit:** a user can install Kite on a clean device, securely sign in, verify it, recover encrypted history, lock the app, and manage sessions without needing Element X.

**Verification note (2026-09-17):** homeserver selection/discovery, password login, session restore, and soft logout are production-backed through `MatrixAccountSdkGateway` into the native Matrix Rust SDK authentication boundary and encrypted account store. The authentication screen now settles to an explicit authenticated state after successful sign-in instead of leaving login controls mounted. Native sync terminal-auth failures are mapped to an expired-session state without retry loops, production runtime invalidation returns the user to same-account reauthentication, and stale expiry callbacks are discarded across account/runtime changes. Focused auth/controller/session/native-boundary tests and scoped analysis pass, and the full `tool/quality_gate.sh` passes including Rust/ABI verification, the deterministic Flutter suite, the locked Waydroid PASS → expected FAIL → PASS jitter harness, and back-navigation profile gate. OIDC, SSO, QR login, registration, verification, and recovery remain unchecked because the current native production boundary still reports those capabilities unsupported.

**Session-device progress (2026-09-18):** production session listing now uses Matrix Rust SDK device and crypto-device state for current-device identification, display metadata, and verification state. Remote device sign-out uses SDK `Client::delete_devices` with password UIA reauthentication; the password remains transient, is forwarded untrimmed only for the mutation, and is never persisted or surfaced in diagnostics. Inactive-account guards remain intact. ABI 24 Android JNI libraries were rebuilt for arm64-v8a, armeabi-v7a, and x86_64 and verified in a release APK. Focused Flutter coverage passes 99 tests with 3 intentional native-library skips, Rust formatting/check plus all 9 bridge tests pass, full analysis is clean, and `tool/quality_gate.sh` passes release audit, Rust/ABI verification, analysis, and all 1,046 deterministic Flutter tests with 3 intentional native-library skips before stopping at the required Waydroid jitter stage because Glass has no ADB device. Session/device parity checkboxes remain unchecked until that device gate can run.

## Milestone 3 — Home, room list, filters, Sections, invites, and Spaces

- [ ] Element X-quality home header/profile treatment.
- [ ] Fast room list with stable scroll position during sync.
- [x] Correct latest-event previews and sender attribution.
- [x] Unread counts.
- [x] Mention indicators.
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

**Verification note (2026-09-17):** production Rust sync now carries Matrix notification/highlight counts and sender display names into the persisted presentation cache. Room-list unread counts and mention indicators are cache-first, survive restart, and update through leaf Signals without changing room-order identity. Latest-event previews now use event-aware labels for media/voice events and real message bodies for text-like events, while sender attribution prefers the SDK-backed display name with user-ID fallback. Focused codec/cache/store/home/timeline tests, Rust bridge tests, scoped analysis, and the full `tool/quality_gate.sh` pass.

**Favourite-state progress (2026-09-17):** production Matrix favourites are now read from SDK sync, persisted through the native Matrix Rust SDK boundary, reflected optimistically from the room contextual menu with failure rollback, and retained in the presentation cache across restart without changing room-order identity. Focused Flutter/Rust tests, scoped analysis, release audit, ABI verification, and the 998-test Flutter suite pass. The checkbox remains intentionally unchecked because Glass currently has no Waydroid/ADB device, so the required locked jitter phase of `tool/quality_gate.sh` could not run.

**Muted-room progress (2026-09-17):** production sync now reads explicit room mute state from the Matrix Rust SDK notification-settings cache, persists it in Kite's presentation cache, and projects it into the existing restrained room-list mute decoration and quiet activity marker. Muted rooms with unread activity use the quiet marker rather than unread-count chrome while mentions remain visible. Focused Flutter tests, scoped analysis, `cargo check`, and all 7 Rust bridge tests pass; `tool/quality_gate.sh` also passed the release audit, Rust/ABI stages, and the 998-test Flutter suite with 3 intentional native-library skips before stopping at the required Waydroid jitter stage because Glass currently has no ADB device. The muted-room and muted-activity checkboxes remain unchecked until that locked device gate can run.

**Active-call progress (2026-09-17):** production Rust sync now reads MatrixRTC room-call membership through the Matrix Rust SDK's `Room::has_active_room_call()`, carries that state through the Dart sync model, persists it in the presentation cache across restart, and projects it into the existing restrained room-list call decoration without changing room ordering. Focused codec/cache/store/home tests, room-row coverage, scoped analysis, `cargo check`, and all 7 Rust bridge tests pass. The active-call checkbox remains unchecked because Glass still has no ADB device for the required locked `tool/quality_gate.sh` jitter phase.

**Read-all progress (2026-09-17):** the contextual authenticated-home account sheet now exposes production-backed “Mark all as read” without adding permanent home chrome. Kite sends an unthreaded Matrix SDK read receipt to the latest cached event in each unread/highlight room through the Rust boundary, clears successful room unread/highlight leaves in the presentation cache, persists the resulting cache state, and continues remaining rooms if one receipt fails. The native ABI was bumped and Android JNI libraries rebuilt for arm64-v8a, armeabi-v7a, and x86_64; an Android release APK builds successfully. Focused Flutter coverage passes, `cargo check` and all 7 Rust bridge tests pass, full analysis is clean, and `tool/quality_gate.sh` passes release audit, Rust/ABI verification, analysis, and the 1001-test Flutter suite with 3 intentional native-library skips before stopping at the required Waydroid jitter phase because Glass has no ADB device. The read-all checkbox remains unchecked until that device gate can run.

**Invite-flow progress (2026-09-17):** production Matrix sync now carries pending-room invite metadata from the audited Matrix Rust SDK into Kite's persisted presentation cache, while joined-room ordering remains untouched. Pending invites are discoverable from the existing account sheet rather than permanent home chrome; the secondary invite sheet supports SDK-backed accept (`Room::join`) and decline (`Room::leave`) with pending/failure states and keeps successful local dismissals hidden until sync confirms removal. ABI 12 Android JNI libraries were rebuilt for arm64-v8a, armeabi-v7a, and x86_64 and verified inside a release APK. Focused codec/cache/store/home/native tests and native ABI smoke coverage pass. `tool/quality_gate.sh` passes release audit, Rust/ABI verification, full analysis, and the 1004-test Flutter suite with 3 intentional skips before stopping at the required Waydroid jitter phase because Glass has no ADB device. The invite checkbox remains unchecked until that locked device gate can run.

**Room-filter progress (2026-09-17):** All, Unreads, People/DMs, Rooms, and Favourites now compose with the production room list through a secondary “Filter chats” sheet opened from the existing home account/menu surface, without adding persistent filter bars, chips, or other homepage chrome. Matrix Rust sync reads `Room::is_direct()` and carries direct-room state through the Dart codec and persisted presentation cache, so People/Rooms filtering remains correct after restart instead of relying on fixtures. Search composes with the selected filter, and constrained-height account sheets scroll rather than overflow. Android JNI libraries were rebuilt for arm64-v8a, armeabi-v7a, and x86_64, and a release APK containing all three updated libraries builds and verifies. Focused Flutter tests, scoped analysis, `cargo check`, and all 7 Rust bridge tests pass. `tool/quality_gate.sh` passes release audit, Rust/ABI verification, full analysis, and the 1005-test Flutter suite with 3 intentional skips before stopping at the required Waydroid jitter phase because Glass has no ADB device. The room-filter checkbox remains unchecked until that locked device gate can run.

**People-search progress (2026-09-18):** the existing secondary New conversation screen now searches the production Matrix user directory by user ID or display name through `matrix-sdk`'s `Client::search_users`, with debounced stale-result-safe UI, explicit search failure state, and result selection feeding the existing encrypted DM creation path. The search remains off the primary home surface. Focused UI/runtime/native tests, Rust formatting/check/tests, full analysis, native-library smoke coverage, and an Android release APK with all three rebuilt JNI ABIs pass. The people-search checkbox remains unchecked until the required locked Waydroid quality gate can run on an available ADB device.

**Home-interaction consolidation (2026-09-24):** the fixed bottom search keeps “Create room” as the first contextual action and now adds a secondary “Start conversation” action that feeds the existing Matrix people-search flow without restoring a FAB or permanent homepage chrome. Existing DMs resolve through the production direct-message open path and focus the synced room without replacing its cached state. The profile sheet omits New conversation and Mark all as read, phone chats support left-edge swipe-back dismissal, and the desktop room context menu exposes confirmed Leave room / Delete chat actions. Validation passes flutter analyze, 49 focused Flutter tests, the 1,142-test deterministic suite with 5 intentional skips, the release audit, 13 serialized Rust bridge tests, and 23 native ABI smoke tests. The locked Waydroid performance gate still fails on the shared SwiftShader raster baseline: cold-open raster was 37,699 µs on this branch versus 38,365 µs on untouched main, and back-navigation raster was 20,581 µs on this branch versus 36,059 µs on untouched main, with zero build-thread violations in all four runs. The affected roadmap checkboxes remain unchecked until the device raster gate itself is green.

## Milestone 4 — Timeline rendering and message state

- [x] Virtualised timeline capable of very large histories without retaining every rendered widget.
- [x] Stable scroll anchoring when events arrive above/below the viewport.
- [x] Stable scroll anchoring during back-pagination.
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

**Reply progress (2026-09-18):** the existing reply composer now preserves the target event through the production send stack and emits a proper Matrix `m.in_reply_to` relation through the audited Rust SDK path instead of degrading to plain text. Synced Matrix reply relations project back into Kite reply previews using cached target sender/body metadata while preserving timeline order and existing message identity. The native boundary is ABI 21; Rust formatting/check/tests, focused timeline motion/projection/runtime/native tests, full analysis, native-library smoke coverage, and an Android release APK with all three rebuilt JNI ABIs pass. Reply-related checkboxes remain unchecked until the required locked Waydroid quality gate can run on an available ADB device.

**Pagination-anchor completion (2026-09-18):** the reversed timeline now keeps the existing visible sliver anchored while older events are prepended, without retaining the newly loaded offscreen rows. Deterministic 120 Hz tests cover both synced tail insertion while scrolled away from the tail and back-pagination while retaining an existing visible event. The full `tool/quality_gate.sh` passes on Glass with the active locked Waydroid device, including release audit, Rust/ABI verification, analysis, deterministic Flutter tests, jitter PASS → expected FAIL → PASS, and back-navigation profile verification.

**Timeline-virtualisation completion (2026-09-18):** a deterministic 2,000-event widget test now verifies that Kite retains the complete timeline model while mounting fewer than 200 message bubbles both at the tail and after substantial scrolling. The oldest offscreen row remains unmounted at the initial tail position, proving the large-history timeline is backed by lazy slivers rather than a fully retained rendered list.

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

**Edit-message progress (2026-09-18):** the existing edit composer now sends production Matrix `m.replace` events through the audited Rust SDK path instead of mutating only local Signals. Replacement events fold back into the original timeline message identity, preserve ordered edit history without adding duplicate rows, reject cross-sender replacement attempts, and optimistic edits roll back on send failure without allowing a stale failure to undo a newer edit. Room-list previews use `m.new_content` rather than Matrix's fallback edit body. The native boundary is ABI 22; focused controller/presentation/runtime/native tests, Rust checks/tests, and Android JNI builds pass. The edit checkbox remains unchecked until the required locked Waydroid quality gate can run on an available ADB device.

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
  - 2026-09-23 progress: profile avatars open the shared hero-transition media viewer; regular avatar requests stay at 192px while the visible full-screen avatar requests 1600px media. Behavior, 120 Hz motion, full Flutter tests, analyze, and release audit pass. Keep this unchecked until the required device jitter gate completes for this branch.
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
- [ ] Invite members.
- [x] Roles/power levels.
- [ ] Promote/demote where authorised.
- [ ] Kick.
- [ ] Ban/unban.
- [ ] Report user/room where supported.
- [ ] Leave room.
- [ ] Forget/remove local room state where relevant.
- [ ] Convert/use DM semantics correctly when SDK room metadata changes.

**Verification note (2026-09-17):** production room creation now reaches `matrix-sdk` through the Rust bridge for direct messages, private rooms, and public rooms, including safe encryption/history defaults, server-side invites, public/private visibility, local room-address creation, and sender-side `m.direct` metadata for DMs. The entry point lives in the contextual account sheet so the search-first home surface stays unchanged. Focused room-creation/native tests, full Flutter analysis, Rust tests, and an Android release APK build passed; `tool/quality_gate.sh` additionally passed release audit, ABI smoke, and all 1,008 deterministic Flutter tests before stopping at the Waydroid jitter stage because Glass has no Waydroid ADB device. The three creation checkboxes remain intentionally unchecked until that required performance gate can run.

**Verification note (2026-09-16):** production room details now load joined members and effective power levels through the Matrix Rust SDK boundary, and the real-account Linux smoke path verifies that the member directory is not fixture data. Invite, power-level mutation, kick, and ban/unban remain unchecked until their production Matrix mutation ports are wired; deterministic fixture/controller coverage alone is not counted as parity completion.

**Invite-member progress (2026-09-17):** room details now wires the existing secondary Members flow to a production Matrix Rust SDK `Room::invite_user_by_id()` mutation through the native boundary, account runtime, and inactive-account guard. Production keeps unfinished report/leave/role/kick/ban controls hidden while retaining member search and invitation, and invalid or server-denied invitations surface through the existing deterministic failure state. ABI 14 Android JNI libraries were rebuilt for arm64-v8a, armeabi-v7a, and x86_64; a release APK builds and contains all three updated libraries. Focused Flutter coverage, clean scoped/full analysis, all 7 Rust bridge tests, release audit, ABI smoke coverage, and the 1,012-test Flutter suite with 3 intentional native-library skips pass. `tool/quality_gate.sh` stops only at the required Waydroid jitter stage because Glass currently has no Waydroid ADB device, so the invite-members checkbox remains unchecked until that device gate can run.

**Room-moderation progress (2026-09-17):** the existing member-management UI now routes role changes, kick, ban, and unban through SDK-derived Matrix power-level authorization and production Matrix Rust SDK mutations instead of fixture-only mutation ports. The native bridge exposes current room permissions plus `Room::update_power_levels`, `Room::kick_user`, `Room::ban_user`, and `Room::unban_user`; inactive-account guards and failure propagation remain intact. ABI 15 JNI libraries were rebuilt for arm64-v8a, armeabi-v7a, and x86_64, and a release APK builds with all three libraries verified. Focused moderation/runtime/native tests pass, Rust `cargo check` plus all 7 bridge tests pass, scoped analysis is clean, and `tool/quality_gate.sh` passes release audit, Rust/ABI verification, full analysis, and the 1,013-test Flutter suite with 3 intentional native-library skips before stopping only at the required Waydroid jitter stage because Glass has no Waydroid ADB device. Promote/demote, kick, and ban/unban remain unchecked until that device gate can run.

**Room-safety progress (2026-09-17):** room/member reporting, leave, and forget now route from the existing secondary room-members action menu through the production account runtime into audited Matrix Rust SDK primitives, with inactive-account guards and native-response validation. Production moderation/safety actions are enabled instead of fixture-only, and Matrix sync now removes left rooms and their cached timelines from the presentation cache without disturbing peer room identity or order; cold-sync chunking defers removals until the cursor-committing final chunk. ABI 16 JNI libraries were rebuilt for arm64-v8a, armeabi-v7a, and x86_64 and verified inside a release APK. Focused room-safety/cache/native tests, full analysis, Rust formatting/check/tests, and the Android release build pass. `tool/quality_gate.sh` passes the release audit, Rust/ABI stages, full analysis, and the 1,017-test Flutter suite with 3 intentional native-library skips before stopping only at the required Waydroid jitter stage because Glass has no ADB device. Report, leave, and forget remain unchecked until that device gate can run.

**Room-settings progress (2026-09-17):** the existing secondary Room settings screen now reads and mutates production Matrix room state through the audited Rust SDK boundary for name, topic, existing MXC avatar state, canonical alias, supported join rule, one-way encryption enablement, history visibility, and per-room notification mode. The native bridge validates room-setting responses, keeps FFI/JSON work off the UI isolate, and retains inactive-account guards through the account runtime. ABI 17 JNI libraries were rebuilt for arm64-v8a, armeabi-v7a, and x86_64 and verified in a release APK. Focused room-management/settings/native tests, Rust formatting/check/tests, full analysis, and the Android release build pass; `tool/quality_gate.sh` passes the release audit, Rust/ABI stages, analysis, and the 1,018-test Flutter suite with 3 intentional native-library skips before stopping at the required Waydroid jitter stage because Glass has no ADB device. Room-setting checkboxes remain unchecked until that device gate can run; name/topic/avatar editing also remains incomplete until production avatar media selection/upload is wired rather than relying on an already-uploaded MXC URI.

## Milestone 10 — User profile, settings, notifications, privacy, and account management

- [ ] View own profile.
- [ ] Edit display name and avatar.
- [ ] View another user's profile/avatar.
- [ ] Start/open DM from user profile.
- [ ] Ignore/block controls supported upstream.
- [x] Account management and sign out.
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

**Profile-safety progress (2026-09-18):** the existing user-profile and privacy surfaces now expose the single upstream-equivalent Block/Unblock state instead of duplicate Ignore and Block controls. Production routes that state through `matrix-sdk`'s stored ignored-user list plus `Account::ignore_user` / `Account::unignore_user`, with inactive-account guards, native-response validation, and the same SDK-backed state available to privacy management. ABI 23 JNI libraries were rebuilt for arm64-v8a, armeabi-v7a, and x86_64 and verified inside a release APK. Focused profile/privacy/runtime/native tests, inspected light/dark golden diffs, Rust formatting/check/tests, full analysis, and the Android release build pass; `tool/quality_gate.sh` passes release audit, Rust/ABI stages, analysis, and the 1,043-test Flutter suite with 3 intentional native-library skips before stopping only at the required Waydroid jitter stage because Glass has no ADB device. The ignore/block parity checkbox remains unchecked until that device gate can run.
- [ ] Badge counts and clear-on-read behaviour.
- [ ] Privacy/security settings.
- [ ] Session/device management.
- [ ] App lock settings.
- [x] Cache/storage management without destroying diagnostic logs unexpectedly.
- [x] Report-a-problem flow with sanitised logs.
- [x] About/version/licenses.
- [ ] Developer settings only where they are genuinely useful; never leak Matrix complexity into normal settings.

**Verification note (2026-09-17):** production sign-out is reachable from a compact authenticated-home account menu without adding permanent dashboard chrome. Kite first stops and closes the active Matrix runtime, then invalidates the server session through the Matrix SDK and removes restore metadata plus that account's encrypted SDK store. The simplified-home adaptive expectation and intentional room-list/thread golden baselines were reconciled without restoring removed header/filter chrome. JSON parsing and native Matrix response decoding now remain behind background-isolate boundaries, covered by the architecture contract. Full `tool/quality_gate.sh` passes, including the release audit, 7 Rust bridge tests, clean Flutter analysis, native ABI smoke coverage, the 991-test Flutter suite with 3 intentional native-library skips, and the locked Waydroid jitter/back-navigation gates.

**Profile progress (2026-09-18):** own-profile loading and display-name mutation reach the audited Matrix Rust SDK through the production account runtime, and the existing account identity row opens the profile as a secondary screen without adding home-screen chrome. Target-user profile loading and open/create-DM primitives are production-backed through the same boundary. Production avatar editing uses the cross-platform system file selector, uploads validated image bytes through the Matrix SDK media API off the Flutter UI isolate, and applies the returned MXC URI through the existing profile mutation flow. Production MXC avatar rendering now downloads SDK-managed media thumbnails through the native boundary off the Flutter UI isolate and feeds Flutter's image cache with account/runtime isolation instead of falling back to initials. The native boundary is ABI 20; Android JNI libraries were rebuilt for arm64-v8a, armeabi-v7a, and x86_64 and a release APK verifies all three updated libraries. Focused profile/runtime/native tests, Rust formatting/check/tests, full analysis, and Android release packaging pass. Profile checkboxes remain unchecked until the required locked Waydroid quality gate can run on an available ADB device.

## Milestone 11 — Notifications and deep-link correctness

- [x] FCM-compatible push path where applicable.
- [x] Non-Google/background sync notification path where required for distribution targets.
- [x] Message notifications.
- [x] Mention notifications.
- [x] Invite notifications.
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
  - Progress 2026-09-24: the shared locale formatter now drives synced timeline times and date separators, invite/Space member and room counts, and room-list unread badges plus accessibility labels. A German widget regression verifies a four-digit unread count renders as 1.234 rather than 1,234. Focused home, Spaces, motion, localization, and date-separator coverage passes, full analysis is clean, and the full Flutter suite passes 1,143 tests with 5 intentional native-library skips. Keep unchecked until the remaining user-visible numeric/duration/storage labels are audited and the required runtime quality gate is green.
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
- [x] Thread open/switch benchmark.
- [ ] Media viewer benchmark.
  - Progress 2026-09-24: the existing deterministic profile benchmark is now runnable through `tool/verify_media_viewer_harness.sh` under the shared Waydroid lock. The locked run reached the benchmark but failed the unchanged 16,666 µs raster contract across media-open/dismiss/swipe/save/audio/timeline-media journeys (for example, media-open worst raster 105,737 µs) while build violations remained zero. Keep unchecked until the repository-wide Waydroid raster baseline is fixed; thresholds were not weakened.
- [x] Call-screen transition benchmark.
- [ ] App startup benchmark.
- [x] Offline recovery benchmark.
- [x] Memory-growth soak test while switching rooms and paginating.
- [x] Image/media cache pressure test.
- [x] Repeated login/logout/account-switch store-cleanup test.
- [ ] Thermal/low-memory/background-kill testing on physical Android hardware.
- [ ] Physical Android Macrobenchmark matrix on at least one 60 Hz and one 120 Hz device.
- [ ] No accepted performance regression without before/after evidence and an explicit product decision.

**Media-startup progress (2026-09-24):** production startup now warms recent Matrix images from the presentation cache, coalesces duplicate media loads, batches native SDK media prefetch work, and prioritises visible media ahead of queued speculative requests. A production-session integration benchmark now records saved-session startup → three painted avatars and room-open → recent-image paint latency without fixture prefetch or cache clearing. Focused Flutter coverage, Rust formatting plus all 13 bridge tests, native-library ABI smoke coverage (22 tests), full analysis, release audit, and all 1,134 deterministic Flutter tests pass with 5 intentional no-native-library skips. The required locked Waydroid jitter baseline remains independently blocked: this branch measured 36,951 µs cold-open raster and clean origin/main measured 36,577 µs on the same device against the 16,666 µs contract, so the app-startup/media performance checkboxes remain unchecked and thresholds were not weakened.

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
