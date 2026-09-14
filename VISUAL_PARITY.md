# Kite visual parity audit

Kite's visual target is the current Element X Android `develop` branch while retaining Kite branding and assets. This file records reproducible visual comparisons without vendoring Element artwork or screenshots.

## Reference baseline

Reference branch: `element-hq/element-x-android` `develop`.

Reference commit audited on 2026-09-15: `3d198d8065030820f0ad2ed06fff65d6928112f3`.

The audit re-resolved `refs/heads/develop` immediately before comparison. Since the prior audit SHA (`8cd3750cde65c8bbfc97cb578d00111b6bf62ee8`), upstream advanced by one commit: `3d198d806503` (`Fix flaky test in TimelinePresenterTest`, #7702). The compare touches timeline/controller wiring and tests only, with no screenshot, feature-flag, release, or generally available user-facing feature delta to schedule in this pass. The current home LFS snapshots were fetched again at the new SHA for the rendered comparison below.

Current Element X screenshot tests live under `tests/uitests/src/test/snapshots/images/` and are generated from public Composable previews. Relevant home references for this pass:

- `features.home.impl.components_HomeTopBar_Day_0_en.png`
- `features.home.impl.components_HomeTopBar_Night_0_en.png`
- `features.home.impl.components_RoomListContentView_Day_0_en.png`
- `features.home.impl.components_RoomListContentView_Night_0_en.png`
- `features.home.impl.components_RoomSummaryRow_Day_0_en.png`
- `features.home.impl.components_RoomSummaryRow_Night_0_en.png`

Kite comparison renders are produced by `test/golden_gallery_test.dart` in:

- `test/goldens/gallery/home_phone_portrait_{light,dark}.png`
- `test/goldens/gallery/home_phone_landscape_{light,dark}.png`
- `test/goldens/gallery/home_tablet_{light,dark}.png`
- `test/goldens/gallery/home_desktop_{light,dark}.png`

Relevant current Element X message references used for the DM/composer review are:

- `features.messages.impl.timeline.components_TimelineItemEventRowForDirectRoom_Day_0_en.png`
- `features.messages.impl.timeline.components_TimelineItemEventRowForDirectRoom_Night_0_en.png`
- `features.messages.impl.messagecomposer_MessageComposerView_Day_0_en.png`
- `features.messages.impl.messagecomposer_MessageComposerView_Night_0_en.png`

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
| Home header, light | Profile/avatar anchors the left; large `Chats` title; search and filter actions on the right; filter chips below; subtle contextual bloom behind the top region. | Portrait currently shows only the `Chats` title in a fixed header. No profile action, search/filter actions, filter chips or bloom yet. | `home_phone_portrait_light.png`; compare with `HomeTopBar_Day_0_en.png`. | Gap |
| Home header, dark | Same hierarchy as light with restrained dark surfaces and clear action contrast. | Portrait dark preserves the same minimal title-only hierarchy. | `home_phone_portrait_dark.png`; compare with `HomeTopBar_Night_0_en.png`. | Gap |
| Room-list row | Avatar, strong room name, quiet preview metadata, trailing time/state treatment; invite/loading variants reserve stable row geometry. | Current deterministic room rows provide avatar initial, title and one-line subtitle; timestamps, unread/mention states and richer variants are not implemented. | Home phone/tablet/desktop gallery; compare with `RoomListContentView_*` and `RoomSummaryRow_*`. | Gap |
| Phone portrait shell | Element X uses a single primary content pane with top-level home navigation. | Kite uses single-pane room navigation and pushes the selected conversation without retaining a split pane. | `adaptive_layout_test.dart`; `home_phone_portrait_*`. | Geometry covered; parity incomplete |
| Phone landscape shell | Compact layout stays single-pane rather than squeezing a desktop split view into the short axis. | Kite uses the same single-pane rule based on shortest side. | `adaptive_layout_test.dart`; `home_phone_landscape_*`. | Geometry covered; parity incomplete |
| Tablet shell | Element X adapts composition for larger displays rather than simply scaling phone content. | Kite uses a stable 300 px room-list pane plus conversation pane. | `adaptive_layout_test.dart`; `home_tablet_*`. | Adaptive baseline covered; parity incomplete |
| Desktop-width shell | Wide layout should preserve mobile visual language while adding useful simultaneous context. | Kite uses a stable 320 px room-list pane plus conversation pane. | `adaptive_layout_test.dart`; `home_desktop_*`. | Adaptive baseline covered; parity incomplete |
| DM timeline | Element X uses production message grouping, event states, receipts, reactions and stable jump/focus behaviour. | Kite now renders distinct incoming/own rows with sender/avatar context, timestamps and status affordances, but rows remain broader and reaction/receipt/media treatment is incomplete. | `home_tablet_*`, `home_desktop_*`; compare with `TimelineItemEventRowForDirectRoom_*`. | Reviewed; gaps remain |
| Group-room timeline | Element X adds group-specific sender/state-event hierarchy on top of the timeline system. | Kite has no group-room-specific rendered treatment yet. | None yet. | Not audited |
| Composer / rich text | Element X uses a compact production composer with formatting, reply/edit/media and expansion states. | Kite has a deterministic rounded composer with attachment/input/send regions, but voice, rich-text formatting, expansion and several production states remain incomplete. | `home_tablet_*`, `home_desktop_*`; compare with `MessageComposerView_*`. | Reviewed; gaps remain |
| Message actions / reactions | Element X uses contextual actions, reaction summaries/pickers and destructive confirmations. | Not yet present in current Kite top-level UI. | None yet. | Not audited |
| Threads | Current `develop` retains thread feature flags/Labs direction and dedicated thread timeline concepts. | Not yet present in current Kite top-level UI. | None yet. | Not audited |
| Spaces | Element X ships dedicated Space discovery/navigation flows and hierarchy. | Not yet present in current Kite top-level UI. | None yet. | Not audited |
| Room creation / invites | Element X has dedicated creation, invitation, join/knock and invite-preview states. | Not yet present in current Kite top-level UI. | None yet. | Not audited |
| Room details / moderation | Element X has dedicated room details, membership and moderation flows. | Not yet present in current Kite top-level UI. | None yet. | Not audited |
| User profile | Element X has dedicated own/other-user profile and DM-entry states. | Not yet present in current Kite top-level UI. | None yet. | Not audited |
| Settings / security | Element X has appearance, notifications, privacy, sessions, verification, backup and app-lock settings. | Not yet present in current Kite top-level UI. | None yet. | Not audited |
| Poll / location / media | Element X renders dedicated event, picker/viewer and permission/error states for these content types. | Not yet present in current Kite top-level UI. | None yet. | Not audited |
| Calls | Element X has incoming, outgoing and in-call states integrated with MatrixRTC/Element Call. | Not yet present in current Kite top-level UI. | None yet. | Not audited |
| Empty / loading / error / offline | Element X reserves geometry with explicit empty/loading/error/offline states. | Current benchmark home state does not yet expose representative variants. | Home reference comparison only. | Gap |
| Theme variants | Element X references cover day/night; black theme remains behind an unfinished feature flag in current `develop`. | Kite gallery covers light/dark; true-black is not implemented. | Home light/dark gallery. | Gap |

## Current conclusion

The adaptive/golden infrastructure is reviewable and deterministic, but the home visual hierarchy is not yet Element X-quality. In particular, current Kite renders must not be used to close the home hierarchy, density, avatar treatment, full visual-audit, or final parity checkboxes. Lane 3 can add the missing home behaviour while lane 5 keeps the visual/reference contract and rendered comparisons current.
