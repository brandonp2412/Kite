# Kite visual parity audit

Kite's visual target is the current Element X Android `develop` branch while retaining Kite branding and assets. This file records reproducible visual comparisons without vendoring Element artwork or screenshots.

## Reference baseline

Reference branch: `element-hq/element-x-android` `develop`.

Reference commit audited on 2026-09-15: `8cd3750cde65c8bbfc97cb578d00111b6bf62ee8`.

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

Flutter widget-test goldens use the deterministic test font, so they are authoritative for geometry, colour, clipping and layout stability but not final typography appearance. Typography review must also use an app render on a real Flutter target before a visual-parity checkbox can close.

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
| Timeline / composer | Current Element X uses a richer production timeline/composer hierarchy with multiple event/action states. | Kite fixture is intentionally minimal and benchmark-oriented today. | Existing shell/gallery only. | Not audited |
| Threads / Spaces | Dedicated upstream flows and states exist. | Not yet present in current Kite top-level UI. | None yet. | Not audited |
| Room/user details | Dedicated upstream detail flows exist. | Not yet present in current Kite top-level UI. | None yet. | Not audited |
| Settings/security | Dedicated upstream settings/security flows exist. | Not yet present in current Kite top-level UI. | None yet. | Not audited |
| Calls/media/polls/location | Dedicated upstream flows and state-specific visuals exist. | Not yet present in current Kite top-level UI. | None yet. | Not audited |

## Current conclusion

The adaptive/golden infrastructure is reviewable and deterministic, but the home visual hierarchy is not yet Element X-quality. In particular, current Kite renders must not be used to close the home hierarchy, density, avatar treatment, full visual-audit, or final parity checkboxes. Lane 3 can add the missing home behaviour while lane 5 keeps the visual/reference contract and rendered comparisons current.
