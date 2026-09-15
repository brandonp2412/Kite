# Kite visual parity audit

Kite's visual target is the current Element X Android `develop` branch while retaining Kite branding and assets. This file records reproducible visual comparisons without vendoring Element artwork or screenshots.

## Reference baseline

Reference branch: `element-hq/element-x-android` `develop`.

Reference commit audited on 2026-09-15: `ba80abcbf0f5238940fea9b7a6b22f7a8bc518ac`.

The audit re-resolved `refs/heads/develop` immediately before comparison. Since the previous audited SHA (`3d198d8065030820f0ad2ed06fff65d6928112f3`), upstream advanced by five commits. GitHub's compare reports changes only to `.github/workflows/tests.yml`, `build.gradle.kts`, and `gradle/libs.versions.toml`; the commits are build/test tooling and dependency maintenance, with no screenshot, feature-flag, release, or generally available user-facing feature delta to schedule in this pass. The current home, room-row, and direct-room timeline LFS snapshots were fetched again at the new SHA for the rendered comparisons below.

Current Element X screenshot tests live under `tests/uitests/src/test/snapshots/images/` and are generated from public Composable previews. Relevant home references for this pass:

- `features.home.impl.components_HomeTopBar_Day_0_en.png`
- `features.home.impl.components_HomeTopBar_Night_0_en.png`
- `features.home.impl.components_RoomListContentView_Day_0_en.png`
- `features.home.impl.components_RoomListContentView_Night_0_en.png`
- `features.home.impl.components_RoomSummaryRow_Day_0_en.png`
- `features.home.impl.components_RoomSummaryRow_Night_0_en.png`

Kite comparison renders are produced by `test/golden_gallery_test.dart` in the canonical gallery set:

- `test/goldens/home_phone_portrait_{light,dark,true_black}.png`
- `test/goldens/home_phone_landscape_{light,dark,true_black}.png`
- `test/goldens/home_tablet_{light,dark,true_black}.png`
- `test/goldens/home_desktop_{light,dark,true_black}.png`

The older duplicate `test/goldens/gallery/` set has been removed; it was no longer referenced after the canonical gallery gained all three theme variants and 3× deterministic rendering.

Relevant current Element X message references used for the DM/composer and message-action reviews are:

- `features.messages.impl.timeline.components_TimelineItemEventRowForDirectRoom_Day_0_en.png`
- `features.messages.impl.timeline.components_TimelineItemEventRowForDirectRoom_Night_0_en.png`
- `features.messages.impl.messagecomposer_MessageComposerView_Day_0_en.png`
- `features.messages.impl.messagecomposer_MessageComposerView_Night_0_en.png`
- `features.messages.impl.actionlist_ActionListViewContent_Day_{0..12}_en.png`
- `features.messages.impl.actionlist_ActionListViewContent_Night_0_en.png`
- `features.messages.impl.timeline.components.reactionsummary_ReactionSummaryViewContent_Day_0_en.png`

Relevant current Element X Threads references used for the thread review are:

- `features.messages.impl.topbars_ThreadTopBar_Day_0_en.png`
- `features.messages.impl.threads.list_ThreadsListView_Day_0_en.png`
- `features.messages.impl.threads.list_ThreadsListView_Night_0_en.png`
- `features.messages.impl.timeline.components_ThreadSummaryView_Day_0_en.png`

Relevant current Element X settings references used for the settings/security review are:

- `features.preferences.impl.root_PreferencesRootViewLight_0_en.png`
- `features.preferences.impl.root_PreferencesRootViewDark_0_en.png`
- `features.preferences.impl.notifications_NotificationSettingsView_Day_0_en.png`
- `features.preferences.impl.notifications_NotificationSettingsView_Night_0_en.png`

Flutter widget-test goldens use the deterministic test font, so they are authoritative for geometry, colour, clipping and layout stability but not final typography appearance. Typography review must also use an app render on a real Flutter target before a visual-parity checkbox can close.

### Current upstream feature/release/Labs scan

The current `features/` tree was re-scanned at the reference SHA. It contains the shipped product areas expected by the roadmap, including home, messages, calls/room calls, room creation/details/directory/moderation, invites, Spaces, polls, location, security/backup/verification, preferences, profiles, sharing/forwarding, lock screen, login/logout, content scanning and reporting.

The latest public release at audit time is `v26.09.2` (published 2026-09-10). Its user-facing/reliability changes include push-fetch foreground-service lifetime, cache/remote-config fixes, TalkBack timeline actions, and moving Knock and gallery messages into Labs. Those concerns are already represented by Kite's notification reliability, accessibility, room-join and media/gallery roadmap items.

Current feature flags were also re-read from `FeatureFlags.kt`. Parity-relevant unfinished flags include Threads (Labs), gallery messages (Labs), Knock (Labs), selectable media quality, multi-account, QR login, black theme, jump-to-unread, slash commands, room thread list, automatic back-pagination, unread indicator counts, and local message search. `MessageSearch` remains default-off and is not a generally shipped baseline feature; on-device voice transcription is not present in the scanned feature modules or feature-flag list. These remain scope guards, not blockers inherited from Element Classic.

### Rendered home comparison, 2026-09-15

The current Element X `RoomListContentView_Day_0_en.png` and `HomeTopBar_Day_0_en.png` LFS snapshots were loaded directly from `develop` at the audited SHA and visually compared with Kite's generated `home_phone_portrait_light.png`.

- Geometry stability: Kite's deterministic list rows and viewport are stable, with no loading-induced shifts in the captured state.
- Header hierarchy: Element X has avatar/profile anchoring, a prominent `Chats` title, search/filter actions, filter chips, and a restrained contextual bloom. Kite still has only the title, so this remains a parity gap.
- Room rows: Element X uses stronger title/metadata hierarchy, timestamps/state affordances, invitation actions, and skeleton rows that reserve final geometry. Kite currently has avatar initials, title and one-line preview only, so density/state treatment remains a gap.
- Branding/assets: the comparison is structural only; Kite does not vendor or copy Element trademarks or artwork.

### Rendered DM timeline and composer comparison, 2026-09-15

The current Element X direct-room timeline and composer LFS snapshots were loaded from the same audited `develop` SHA and visually compared with Kite's generated tablet and desktop home renders, which include the selected DM timeline and composer.

- Timeline hierarchy: current Kite now distinguishes incoming and own messages with sender/avatar context, surface treatment, timestamps and delivery/status affordances. This is materially closer to the Element X direct-room reference than the stale pre-change wide gallery baselines.
- Remaining timeline gaps: Element X uses tighter content-width bubbles, more restrained spacing, richer reaction/receipt treatment and production media/event variants. Kite's fixture still reads as wider card rows and does not yet represent the complete production timeline, so parity remains open.
- Composer hierarchy: both products retain a clear leading attachment affordance, central rounded input and trailing send/media action region, but Element X's composer is more compact and has production voice, expansion and disabled-state treatment. Kite's current composer remains simplified.
- Golden decision: the four tablet/desktop home gallery baselines are refreshed to the current deterministic Kite render only after this reference review. This accepts the already-merged runtime geometry as the review baseline; it does not close timeline/composer parity or approve the remaining visual gaps.

### Rendered theme, spacing, icon, and avatar review, 2026-09-15

The current Element X `HomeTopBar`, `RoomSummaryRow`, and direct-room timeline day/night snapshots at `ba80abcbf0f5` were visually compared with Kite's freshly generated light/dark phone and desktop gallery renders. This closes the review work only; it does not claim that the gaps below are implemented.

- Theme surfaces: Kite has coherent light/dark semantic surfaces and preserves row geometry between themes. Element X has a more deliberate dark top-region treatment and contextual bloom. Kite now also has an explicit true-black theme with black canvas/navigation surfaces and matching light system-bar icons; the black gallery preserves the same geometry as light/dark. Current Element X `Night` references remain charcoal rather than pure black, and upstream's separate black-theme feature flag is still unfinished, so Kite's true-black treatment is an intentional Kite visual contract rather than copied upstream artwork.
- Spacing and radii: Kite repeats a consistent row/avatar rhythm and rounded message/composer geometry, but its wide timeline uses looser vertical spacing and broader bubbles than the Element X direct-room reference. Element X's home header also composes title, actions, and filters more tightly without reducing touch-target size.
- Icon sizing: the current Kite gallery has very little top-level icon chrome; this avoids inconsistency but also exposes the missing search/filter/profile affordances already recorded by the home parity gap. Existing composer/action icons are visually stable across light/dark renders.
- Avatar/image treatment: Kite's deterministic room list currently renders circular initial placeholders at stable resolution. Element X demonstrates contextual avatar colour and production image treatment; Kite does not yet exercise high-resolution photo avatars in this gallery, so the visual-quality avatar/bloom and no-upscale implementation contracts remain open.
- Typography: not closed by this review. Flutter goldens use the deterministic test font, so final hierarchy still requires a real-target render with production typography.

### Rendered message-action and reaction comparison, 2026-09-15

The current Element X action-list variants and reaction-summary snapshot were loaded from the audited `develop` SHA and compared with Kite's `timeline_actions_light.png` and `timeline_actions_dark.png` renders.

- Action-sheet structure: Kite now has a deliberate modal scrim, rounded sheet, drag handle, icon-led Reply/Reply in thread/Edit/Copy actions, and a visually distinct destructive Remove action in both themes. The refreshed light/dark captures keep the full action stack inside the bounded sheet without clipping or geometry drift.
- Element X breadth: the current action-list variants add a message preview, quick-reaction row, Forward, Copy link, View source, Report content, content-specific copy actions, and poll actions where applicable. Kite now distinguishes Copy caption for captioned media and exposes Reply in thread, but the remaining link/source/poll breadth still prevents complete action-list parity.
- Reactions: Element X's reaction summary combines selected reaction chips/counts with reactor identity and timestamp detail. Kite's current top-level timeline has no equivalent reaction summary/picker, so reaction parity remains an implementation gap even though the visual review itself is complete.

### Rendered Threads comparison, 2026-09-15

Current Element X `ThreadTopBar_Day_0_en.png`, `ThreadsListView_Day_0_en.png`, `ThreadsListView_Night_0_en.png`, and `ThreadSummaryView_Day_0_en.png` LFS snapshots were loaded directly from the audited `develop` SHA and visually compared with Kite's `thread_light.png`, `thread_dark.png`, following/retry/focus variants, and the thread-unread room-list renders.

- Open-thread hierarchy: both products give the thread a dedicated back affordance, a strong `Thread` title, and room context. Kite additionally keeps follow/unfollow state and reply count in the top region, then separates the root event from replies before the thread composer.
- Thread-state coverage: Kite has deterministic light/dark renders for the normal thread, following state, failed-reply retry state, notification/deep-link focused reply, and room-list thread-unread decoration. The refreshed unread baselines include the same non-colour selected-room weight cue used by the main gallery.
- Threads-list foundation: current Element X has a dedicated Threads list whose rows combine root sender/body/time, reply count, and latest-reply identity/body. Kite now exposes the same core hierarchy in a room-scoped bounded list, with unread count treatment, light/dark desktop references, phone portrait references, and stable thread round-trip navigation. SDK-backed list pagination and the release performance gate remain open, so parity is not yet claimed complete.
- Performance blocker: the first profile-mode Kite thread-open run missed one raster frame at 37,648 µs against the unchanged 16,666 µs budget. Thread pagination passed, but the Milestone 15 thread benchmark remains open until first-open raster cost and the remaining thread journeys pass.

### Rendered room/member and user-profile comparison, 2026-09-15

Kite's `room_members_light.png` and `room_members_dark.png` renders were compared with current Element X `RoomMemberListView_Day_0_en.png`, `RoomMemberListView_Night_0_en.png`, and `UserProfileView_Day_0_en.png` references from the audited SHA.

- Member list: both products provide an obvious people context and search field. Kite's deterministic loaded state adds stable avatar/name/user-ID rows and trailing role labels, while Element X's captured loading state reserves the list region below its search field with a progress affordance.
- Density and width: after the comparison exposed an over-wide desktop list, Kite now centers the member content within the same 720 px readable-content measure used by settings. Search, rows and role metadata retain their mobile rhythm without stretching across the 1200 px baseline.
- User profile gap: Element X gives the profile a strong avatar/name/user-ID hierarchy plus Message/Share actions and security controls such as Verify/Block. Kite has member-profile/moderation foundations but no equivalent full user-profile render in this gallery, so user-profile visual parity remains open.
- Empty/error-state coverage: room members now has deterministic light/dark empty and failed-load renders. A failed initial load presents a dedicated cloud-off state and a visible `Try again` action instead of stacking the generic `No members found` copy under the load error; the broader app-wide empty/loading/error/offline review remains open.

### Rendered settings/security comparison, 2026-09-15

Kite's `GeneralSettingsScreen`, `NotificationSettingsScreen`, and `SupportSettingsScreen` now have deterministic light/dark wide-layout golden baselines in `test/goldens/settings_*`; notifications additionally have matching 390×844 phone baselines. Those actual renders were compared with current Element X settings-root and notification day/night snapshots from the audited SHA.

- Implemented Kite surfaces: appearance/language selection, notification master/categories/per-room mode/sounds, storage/cache controls, sanitised problem reporting, version/build information, and open-source licenses have stable light/dark layouts.
- Hierarchy gap: Element X composes profile/account switching, status, devices, blocked users, notifications, lock screen, encryption, advanced settings, Labs, About, reporting, and analytics into one compact icon-led settings hierarchy. Kite still lacks that unified settings root and several corresponding capability surfaces.
- Responsive composition: the 1200 px Kite settings renders center the settings list within a 720 px maximum content measure instead of stretching rows edge-to-edge, while the phone notification baseline remains edge-to-edge. Capturing the phone state exposed a real dropdown overflow; room mode and sound/ringtone dropdowns now expand within their field width and the 390 px render is overflow-free.
- Security gap: app-lock, verification/recovery, device/account-management, and privacy controllers exist elsewhere in Kite, but the rendered settings surfaces do not yet expose the complete Element X security navigation. Capability parity therefore remains open as recorded in `PARITY_AUDIT.md`.

### Rendered poll/location/media comparison, 2026-09-15

The current Element X poll-event, location-event, and media-viewer snapshots were loaded from the audited SHA and compared with Kite's `media_viewer_light.png` / `media_viewer_dark.png` renders and current timeline fixture.

- Media viewer: both products use an immersive dark canvas with restrained top chrome over the media. A fresh rendered comparison against `MediaViewerView_0_en.png` at the audited SHA exposed Kite's heavier circular controls and centered counter pill; Kite now matches the reference's quieter composition with an icon-only back/share/download row on one translucent top bar, while preserving 48 dp targets, explicit accessibility labels, left/right keyboard paging, caption overlay, adjacent-item paging and deterministic full-resolution replacement. The updated light/dark goldens preserve the same full-screen media geometry.
- Media quality gap: Element X's reference uses production photographic media at display resolution. Kite's deterministic visual is intentionally synthetic, so the no-upscale/high-resolution production-media contract still needs real media-pipeline evidence.
- Poll and location gaps: Element X has dedicated poll choice/results geometry and map/location event cards. Kite now renders deterministic static and live-location cards with fixed geometry, explicit live/ending/ended state, accessible labels, and approved light/dark references. Its composer adds a compact attachment/location action grid plus fixed-geometry light/dark location-share sheets covering static/live preparation, permission denial/recovery, start and stop. Real platform geolocation/permission adapters and Matrix event transport remain open. Poll choice/results UI is still unimplemented.
- Performance verification: the current Waydroid profile-mode media viewer run passed all three journeys with zero build/raster budget violations at the unchanged 16,666 µs budget; repeated open/close recorded one non-gating total-span miss. The Milestone 15 media-viewer benchmark is therefore closed while physical-device release performance remains separately gated.

### True-black rendered comparison, 2026-09-15

The current Element X `HomeTopBar_Night_0_en.png`, `RoomListContentView_Night_0_en.png`, direct-room timeline Night snapshot, and composer Night snapshot were fetched again from the audited `develop` SHA and compared with Kite's generated `home_phone_portrait_true_black.png` and `home_desktop_true_black.png`.

- Surface hierarchy: Element X Night uses a near-black content canvas with a dark charcoal timeline/row vocabulary and a green contextual header bloom. Kite true-black deliberately uses a pure-black canvas/navigation surface while retaining separate dark fields and message surfaces, so controls remain grouped without lifting the entire page off black.
- Contrast and system chrome: Kite's true-black semantic surfaces retain high-contrast foregrounds and the app explicitly selects light status/navigation-bar icons with a black navigation-bar surface. This closes Kite's light/dark/true-black system-bar implementation contract, while minimum-contrast auditing for every state remains open.
- Home gaps remain unchanged by theming: Element X still has profile/search/filter actions, filter chips, timestamps, invite actions, unread affordances and geometry-reserving skeletons that Kite's current home fixture does not yet contain.
- Timeline/composer gaps remain unchanged by theming: Kite's black desktop render keeps incoming/own-message distinction and composer geometry legible, but Element X's current Night reference remains tighter and richer in reactions, receipts, media/event variants and composer states.

## Side-by-side review checklist

For each major screen, compare matching light/dark states at representative phone and wide layouts. Record all gaps before changing a visual-parity checkbox.

- Primary hierarchy: first glance makes title, primary action and current context obvious.
- Information density: secondary metadata is quieter than primary content without becoming illegible.
- Navigation state: selected, unread, mention, muted and active-call states remain distinguishable without relying on colour alone.
- Avatars/media: correct crop, resolution and fallback treatment; no visibly upscaled source.
- Spacing/radii: repeated components use the same spacing and shape grammar.
- Touch/focus: interactive bounds remain accessible and keyboard focus is visible.
- Motion: transitions use Kite motion tokens, preserve geometry, and honour reduced motion.
- Theme: surface hierarchy remains intentional in light, dark and eventual true-black modes.
- Loading/error/offline: placeholders reserve final geometry and never introduce visible layout shift.

## Screen parity matrix

| Screen / state | Element X behaviour / hierarchy | Kite behaviour | Test / render | Status |
| --- | --- | --- | --- | --- |
| Home header, light | Profile/avatar anchors the left; large `Chats` title; search and filter actions on the right; filter chips below; subtle contextual bloom behind the top region. | Portrait currently shows only the `Chats` title in a fixed header. No profile action, search/filter actions, filter chips or bloom yet. | `home_phone_portrait_light.png`; compare with `HomeTopBar_Day_0_en.png`. | Reviewed; gaps remain |
| Home header, dark | Same hierarchy as light with restrained dark surfaces and clear action contrast. | Portrait dark preserves the same minimal title-only hierarchy. | `home_phone_portrait_dark.png`; compare with `HomeTopBar_Night_0_en.png`. | Reviewed; gaps remain |
| Room-list row | Avatar, strong room name, quiet preview metadata, trailing time/state treatment; invite/loading variants reserve stable row geometry. | Current deterministic room rows provide avatar initial, title and one-line subtitle; timestamps, unread/mention states and richer variants are not implemented. | Home phone/tablet/desktop gallery; compare with `RoomListContentView_*` and `RoomSummaryRow_*`. | Gap |
| Phone portrait shell | Element X uses a single primary content pane with top-level home navigation. | Kite uses single-pane room navigation and pushes the selected conversation without retaining a split pane. The current core home/DM flow also survives 200% text scaling without overflow. | `adaptive_layout_test.dart`; `accessibility_layout_test.dart`; `home_phone_portrait_*`. | Layout implemented; broader parity incomplete |
| Phone landscape shell | Compact layout stays single-pane rather than squeezing a desktop split view into the short axis. | Kite uses the same single-pane rule based on shortest side. The core flow survives 200% text scaling without hidden composer actions. | `adaptive_layout_test.dart`; `accessibility_layout_test.dart`; `home_phone_landscape_*`. | Layout implemented; broader parity incomplete |
| Tablet shell | Element X adapts composition for larger displays rather than simply scaling phone content. | Kite uses a stable 300 px room-list pane plus conversation pane. Core layout passes 200% text scaling, but foldable hinge/posture handling is not yet audited. | `adaptive_layout_test.dart`; `accessibility_layout_test.dart`; `home_tablet_*`. | Tablet baseline covered; foldable audit remains |
| Desktop-width shell | Wide layout should preserve mobile visual language while adding useful simultaneous context. | Kite uses a stable 320 px room-list pane plus conversation pane instead of stretching the phone shell. Core layout passes 200% text scaling. | `adaptive_layout_test.dart`; `accessibility_layout_test.dart`; `home_desktop_*`. | Layout implemented; broader parity incomplete |
| DM timeline | Element X uses production message grouping, event states, receipts, reactions and stable jump/focus behaviour. | Kite now renders distinct incoming/own rows with sender/avatar context, timestamps and status affordances, but rows remain broader and reaction/receipt/media treatment is incomplete. | `home_tablet_*`, `home_desktop_*`; compare with `TimelineItemEventRowForDirectRoom_*`. | Reviewed; gaps remain |
| Group-room timeline | Element X adds group-specific sender/state-event hierarchy on top of the timeline system. | Kite has no group-room-specific rendered treatment yet. | None yet. | Not audited |
| Composer / rich text | Element X uses a compact production composer with formatting, reply/edit/media and expansion states. | Kite has a deterministic rounded composer with attachment/input/send regions, but voice, rich-text formatting, expansion and several production states remain incomplete. | `home_tablet_*`, `home_desktop_*`; compare with `MessageComposerView_*`. | Reviewed; gaps remain |
| Message actions / reactions | Element X uses a message preview, quick reactions, contextual actions, reaction summaries/pickers and destructive confirmations. | Kite has a themed action sheet with Reply/Edit/Copy/Remove and destructive confirmation, but quick reactions, Forward, Copy link, View source, reporting and reaction summary/picker UI remain incomplete. | `timeline_actions_{light,dark}.png`; compare with `ActionListViewContent_*` and `ReactionSummaryViewContent_*`. | Reviewed; gaps remain |
| Threads | Current `develop` has a dedicated thread top bar, timeline thread summaries, and a Labs Threads list with root/reply metadata. | Kite opens a dedicated thread route with root context, replies, pagination, composer, follow state, retry/focus states, room-list thread-unread decoration, and a room-scoped bounded Threads list with root/latest-reply metadata and unread counts. SDK-backed list pagination remains unfinished. | `thread_{light,dark}.png`, `thread_list_{light,dark}.png`, `thread_list_phone_{light,dark}.png`, following/retry/focus/unread variants; compare with `ThreadTopBar_*`, `ThreadSummaryView_*`, and `ThreadsListView_*`. | Reviewed; gaps remain |
| Spaces | Element X ships dedicated Space discovery/navigation flows and hierarchy. | Not yet present in current Kite top-level UI. | None yet. | Not audited |
| Room creation / invites | Element X has dedicated creation, invitation, join/knock and invite-preview states. | Not yet present in current Kite top-level UI. | None yet. | Not audited |
| Room details / moderation | Element X has dedicated room details, membership and moderation flows with compact search/member hierarchy. | Kite has a deterministic room-member list/search and member-profile/moderation flows with a centered 720 px wide-layout measure; broader room-details editing/report/leave surfaces remain incomplete. | `room_members_{light,dark}.png`; compare with `RoomMemberListView_*`. | Reviewed; gaps remain |
| User profile | Element X uses a prominent avatar/name/user-ID hierarchy with Message/Share and security actions. | Kite has member-profile foundations but no equivalent full user-profile gallery render or complete own/other-user profile flow. | Room-member gallery plus `UserProfileView_Day_0_en.png` reference. | Reviewed; gaps remain |
| Settings / security | Element X has a compact settings root spanning profile/accounts, notifications, privacy, sessions, verification/backup, app lock, advanced settings and support. | Kite renders appearance/language, notification and support/storage/reporting surfaces in a centered 720 px wide-layout measure; notifications also have overflow-free 390 px phone coverage. Kite still has no unified root and does not yet expose several account/security controller capabilities. | `settings_{general,notifications,support}_{light,dark}.png`, `settings_notifications_phone_{light,dark}.png`; compare with `PreferencesRootView*` and `NotificationSettingsView_*`; capability inventory in `PARITY_AUDIT.md`. | Reviewed; gaps remain |
| Poll / location / media | Element X renders dedicated poll and map/location events plus a production full-screen media viewer. | Kite has a deterministic full-screen media viewer with paging, captions and save/share hooks, plus static/live timeline location cards and a composer location-share flow whose permission/start/stop state changes preserve reserved geometry. Poll UI, real platform location/permission integration, Matrix-backed location ingestion and production media-resolution evidence remain open. | `media_viewer_{light,dark}.png`, `timeline_locations_{light,dark}.png`, `location_share_{light,dark}.png`, `attachment_picker_{light,dark}.png`; compare with `TimelineItemPollView_*`, `TimelineItemLocationView_*`, and `MediaViewerView_*`. | Reviewed; gaps remain |
| Calls | Element X has incoming, outgoing and in-call states integrated with MatrixRTC/Element Call. | Not yet present in current Kite top-level UI. | None yet. | Not audited |
| Empty / loading / error / offline | Element X reserves geometry with explicit empty/loading/error/offline states. | Current benchmark home state does not yet expose representative variants. | Home reference comparison only. | Gap |
| Theme variants | Element X references cover day/night; black theme remains behind an unfinished feature flag in current `develop`. | Kite gallery covers light/dark/true-black with stable geometry and explicit light/dark system-bar icon treatment. | Home light/dark/black gallery. | Implemented/reviewed; broader contrast audit remains |

## Accessibility/adaptive verification, 2026-09-15

`accessibility_layout_test.dart` exercises the currently reachable home/DM shell at 200% text scaling across phone portrait, phone landscape, tablet and desktop viewports. The room-list extent expands under large text and the chat header now grows beyond its 64 dp baseline when necessary; normal-scale gallery geometry is unchanged. It also verifies that a room row exposes a single actionable semantics node containing its title/preview and that the composer attachment/send controls meet the 48 dp minimum touch target. Timeline message bubbles now expose explicit TalkBack custom actions: incoming messages provide Reply and Copy text, while own messages additionally provide Edit message and Delete message. The reversed timeline also assigns chronological `OrdinalSortKey` values so older visible events traverse before newer events; the accessibility test asserts both action labels and `alice-98 < alice-99` traversal order. Keyboard focus now has an explicit 2 px tokenised outline on room rows and actionable message bubbles; focused room rows activate with Enter, and focused message bubbles open their action sheet with Enter, Space, or Shift+F10. The focus changes do not alter unfocused visual baselines: the home gallery and timeline-action golden suite remain byte-for-byte accepted. Settings goldens additionally exercise general, notification and support surfaces at 200% phone text scaling; that coverage found and fixed a fixed-height Support overflow. `media_viewer_test.dart` verifies labelled 48 dp media controls and desktop left/right paging. `design_tokens_test.dart` now gates primary/secondary text and selected-state pairs at 4.5:1 plus unread/mention/destructive indicators at 3:1 across light, dark and true-black themes. `rtl_event_text_test.dart` proves room-list geometry mirrors under RTL directionality and that message bodies choose RTL/LTR paragraph direction from their first strong bidi character independently of the surrounding shell. Generated localisation now also supplies the unread-thread TalkBack plural instead of an English-only inline label; the localisation test verifies both English/NZ and German plural forms in the rendered semantics tree. These tests establish covered-surface evidence only: the roadmap's every-action TalkBack, all-screen large-text, complete focus/keyboard, complete RTL/localised-event coverage, call semantics and exhaustive per-state contrast items remain open. The logical timeline-order roadmap checkbox also remains open until the repository quality gate passes this runtime change; the deterministic/analyze/golden portions pass, but the current Waydroid baseline is raster-gate blocked as recorded in `PERFORMANCE.md`.

## Current conclusion

The adaptive/golden infrastructure is reviewable and deterministic, but the home visual hierarchy is not yet Element X-quality. In particular, current Kite renders must not be used to close the home hierarchy, density, avatar treatment, full visual-audit, or final parity checkboxes. Lane 3 can add the missing home behaviour while lane 5 keeps the visual/reference contract and rendered comparisons current.
