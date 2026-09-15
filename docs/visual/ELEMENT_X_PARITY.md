# Element X visual/parity reference

Baseline refreshed: 2026-09-16

Element X Android reference branch: `develop`
Reference commit: [`3e861cc64645a286a5455e0b47032b1a25b2f49d`](https://github.com/element-hq/element-x-android/commit/3e861cc64645a286a5455e0b47032b1a25b2f49d) (2026-09-15)

Primary sources:

- https://github.com/element-hq/element-x-android/tree/develop
- https://github.com/element-hq/element-x-android-neutrino/blob/develop/docs/screenshot_testing.md
- https://element.io/blog/spaces-has-landed-on-element-x/
- https://element.io/blog/content/images/2026/03/space-list.png
- https://element.io/blog/organise-your-chats-your-way-with-sections/

The official Spaces screenshot is the current public visual reference used for the home/list comparison below. Upstream screenshot tests remain the mechanical reference source for screens that do not have a public marketing screenshot. Kite does not copy Element assets, logos, or brand artwork.

### Current upstream feature-module inventory

The `develop` feature inventory at the reference commit contains: `analytics`, `announcement`, `cachecleaner`, `call`, `contentscanner`, `createroom`, `deactivation`, `enterprise`, `forward`, `ftue`, `home`, `invite`, `invitepeople`, `joinroom`, `knockrequests`, `leaveroom`, `licenses`, `linknewdevice`, `location`, `lockscreen`, `login`, `logout`, `messages`, `migration`, `networkmonitor`, `poll`, `preferences`, `rageshake`, `reportroom`, `rolesandpermissions`, `roomaliasresolver`, `roomcall`, `roomdetails`, `roomdetailsedit`, `roomdirectory`, `roommembermoderation`, `securebackup`, `securityandprivacy`, `share`, `signedout`, `space`, `startchat`, `userprofile`, `verifysession`, and `viewfolder`.

Non-screen support modules such as analytics/network monitoring remain part of the upstream scan, but the matrix below focuses on user-visible screens and flows. The July 2026 Sections reference also confirms that current room-list organisation has moved beyond the older filter-only presentation: named/collapsible sections, room moves, and unread section state now need to be represented in the home parity audit. The public July imagery is useful for hierarchy and density, but is not treated as an Android screenshot unless its source identifies it that way.

## Rendered side-by-side review

### Home / room list

Kite renders checked in this review:

- `test/goldens/home_phone_portrait_light.png`
- `test/goldens/home_phone_portrait_dark.png`
- `test/goldens/home_phone_landscape_light.png`
- `test/goldens/home_phone_landscape_dark.png`
- `test/goldens/home_tablet_light.png`
- `test/goldens/home_tablet_dark.png`
- `test/goldens/home_desktop_light.png`
- `test/goldens/home_desktop_dark.png`
- `test/goldens/home_phone_portrait_true_black.png`
- `test/goldens/home_phone_landscape_true_black.png`
- `test/goldens/home_tablet_true_black.png`
- `test/goldens/home_desktop_true_black.png`

Element X reference: `https://element.io/blog/content/images/2026/03/space-list.png`.

Observed comparison:

| Area | Element X reference | Current Kite render | Result |
| --- | --- | --- | --- |
| Primary hierarchy | Strong top app bar, clear page title, distinct contextual content | Compact layout starts immediately with the room list; no equivalent page-level hierarchy yet | Gap |
| Information density | Compact rows with quiet secondary metadata and clear action affordances | Rows are readable but visually sparse and consume more vertical space | Gap |
| Avatar treatment | High-quality image avatars with shape consistency and contextual state | Deterministic letter avatars only | Gap |
| Navigation | Deliberate top actions and bottom navigation on phone | No phone navigation chrome yet | Gap |
| Selection/unread state | State is carried by shape, iconography, text and colour | Selected state exists but fixture does not exercise equivalent unread/mention hierarchy | Gap |
| Spacing/radii | Consistent compact spacing, soft containers and restrained separators | Tokenised spacing/radii now exist; current fixture still exposes generic list composition | Partial |
| Responsive composition | Reference is phone-first; Element X visual language stays compact | Kite now has explicit compact and two-pane layouts with bounded sidebar width | Partial |
| Theme verification | Upstream screenshot tests gate visual changes | Kite light/dark/true-black goldens gate all current home viewport variants; true-black keeps primary surfaces at `#000000` with restrained near-black elevated surfaces and matching system-bar treatment | Pass for current Kite surface |

Do not approve the home visual-parity roadmap checkbox from this review. The comparison identifies concrete gaps and is intentionally stricter than source-code inspection. The 2026-09-14 true-black render review preserved the same geometry and hierarchy as dark mode. The theme/system-bar implementation is in place, but its roadmap checkbox remains open until the full quality gate passes the pinned cold-frame contract. Shared dialog, sheet, menu, snackbar, and tooltip defaults now also use the same tokenised radii/elevation/surface hierarchy across light, dark, and true-black themes; empty/error/destructive state parity is still open.

### Threads

Kite renders checked in this review:

- `test/goldens/thread_light.png`
- `test/goldens/thread_dark.png`
- `test/goldens/thread_following_light.png`
- `test/goldens/thread_focus_light.png`
- `test/goldens/thread_room_unread_light.png`

Current Element X `develop` references at `3e861cc64645a286a5455e0b47032b1a25b2f49d`:

- [`ThreadTopBar_Day_0_en.png`](https://github.com/element-hq/element-x-android/blob/3e861cc64645a286a5455e0b47032b1a25b2f49d/tests/uitests/src/test/snapshots/images/features.messages.impl.topbars_ThreadTopBar_Day_0_en.png)
- [`ThreadSummaryView_Day_0_en.png`](https://github.com/element-hq/element-x-android/blob/3e861cc64645a286a5455e0b47032b1a25b2f49d/tests/uitests/src/test/snapshots/images/features.messages.impl.timeline.components_ThreadSummaryView_Day_0_en.png)
- [`ThreadsListView_Day_0_en.png`](https://github.com/element-hq/element-x-android/blob/3e861cc64645a286a5455e0b47032b1a25b2f49d/tests/uitests/src/test/snapshots/images/features.messages.impl.threads.list_ThreadsListView_Day_0_en.png)

Observed comparison:

| Area | Element X reference | Current Kite render | Result |
| --- | --- | --- | --- |
| Thread top bar | Compact phone header with back affordance, room avatar, `Thread` title, and quiet room-name subtitle | Clear `Thread`/room-name hierarchy and back affordance, with follow/count actions, but no room avatar in the header | Gap |
| Thread detail composition | Compact Compound hierarchy keeps identity and metadata restrained | Thread root, divider, replies and composer are deliberately composed and tokenised; desktop-width golden is denser and more control-heavy than the upstream phone reference | Partial |
| Thread summary | Compact reply count plus latest-replier avatar/name/preview | Interactive summary exists in the timeline and has motion/semantics coverage, but there is no dedicated light/dark summary golden matching the upstream component state | Gap |
| Threads list | Dedicated list with room identity, parent preview, reply count and latest-reply context | No dedicated Threads list UI exists in `lib/features/threads`; Kite opens thread detail from timeline summaries | Gap |
| State coverage | Day/night snapshots cover top bar, summary and Threads list | Light/dark detail goldens cover following, focused, unread, retry, media and attachment-preview states | Partial |

The Threads review is complete as an audit, not as a parity claim. The roadmap review checkbox can close while the behavioural Threads milestone and visual-parity gaps stay open.

### Message actions / reactions

Kite renders checked in this review:

- `test/goldens/timeline_actions_light.png`
- `test/goldens/timeline_actions_dark.png`
- `test/goldens/timeline_reaction_picker_light.png`
- `test/goldens/timeline_reaction_picker_dark.png`
- `test/goldens/timeline_delete_light.png`
- `test/goldens/timeline_forward_light.png`

Current Element X `develop` references at `3e861cc64645a286a5455e0b47032b1a25b2f49d`:

- [`ActionListViewContent_Day_2_en.png`](https://github.com/element-hq/element-x-android/blob/3e861cc64645a286a5455e0b47032b1a25b2f49d/tests/uitests/src/test/snapshots/images/features.messages.impl.actionlist_ActionListViewContent_Day_2_en.png)
- [`ReactionSummaryViewContent_Day_0_en.png`](https://github.com/element-hq/element-x-android/blob/3e861cc64645a286a5455e0b47032b1a25b2f49d/tests/uitests/src/test/snapshots/images/features.messages.impl.timeline.components.reactionsummary_ReactionSummaryViewContent_Day_0_en.png)

Observed comparison:

| Area | Element X reference | Current Kite render | Result |
| --- | --- | --- | --- |
| Message context | Message identity/preview remains visible at the top of the action surface | The underlying timeline stays visible behind a modal surface, but the selected message is not repeated as a compact preview inside the sheet | Gap |
| Quick reactions | Six large quick-reaction affordances form the first action row | Quick reactions are present as compact pill controls above the action list | Partial |
| Action hierarchy | Flat, icon-led list with generous touch rows and destructive actions clearly separated in red | Rounded centered sheet has clear grouping and destructive colour, but is visually more modal/dense and less phone-native than the upstream surface | Gap |
| Reaction detail | Reaction tabs/counts are prominent, with reactor identity and time below | Kite has a reaction picker and reaction summaries in timeline state, but no matching reactor-detail golden for the upstream reaction-summary screen | Gap |
| Edge-state coverage | Upstream parameterised snapshots include permission/trust/error action variants | Kite goldens cover action, delete, forward, report and picker surfaces, but not the same upstream trust/error variants | Partial |

The message action/reaction review is complete as an audit. It identifies concrete visual and state-coverage gaps; it does not close the underlying message-action or reaction feature boxes.

## Screen-by-screen parity matrix

`Missing` means Kite has no corresponding screen yet. `Foundation` means only shared infrastructure or fixture UI exists. `Partial` means a user-visible slice exists but does not meet the full Element X behavior/visual contract. Tests listed are Kite tests that currently exercise the row.

| Element X area / screen | Element X behaviour reference | Kite behaviour | Kite test | Status |
| --- | --- | --- | --- | --- |
| Home / room list | Activity-sorted conversations, filters, Sections organisation/unread state, invite/state decoration, Spaces entry points | Deterministic room list with selection | `test/widget_test.dart`, `test/adaptive_layout_test.dart`, gallery goldens | Partial |
| Spaces list / discovery | Joined Spaces, filtering/discovery and Space context | No Spaces UI | None | Missing |
| Room timeline | Mixed Matrix event timeline with state, receipts and pagination | Deterministic benchmark messages only | open-DM motion/performance fixtures | Foundation |
| Composer | Rich message composition and send actions | Static text field fixture | gallery goldens | Foundation |
| Threads | Thread summaries, dedicated Threads list, thread timeline/composer, unread/subscription state | Timeline summary, thread detail/composer, pagination, unread/following/focus and thread-scoped media exist; dedicated Threads list is still missing | `test/thread_controller_test.dart`, `test/thread_motion_test.dart`, `test/thread_media_test.dart`, thread goldens | Partial |
| Media viewer / files | Image/video/file viewing and sharing workflows | Full-screen image viewer, adjacent-media browsing, save/share actions and timeline/thread media entry points exist; broader file/video parity remains unfinished | `test/media_viewer_test.dart`, `test/media_viewer_motion_test.dart`, media-viewer goldens | Partial |
| Polls | Poll creation, voting and results | No poll UI | None | Missing |
| Location | Static/live location workflows | No location UI | None | Missing |
| Search / room directory | Current global/room discovery behavior and joined-room filtering | No search UI | None | Missing |
| Create room / start chat | DM, room creation and invite flows | No creation UI | None | Missing |
| Invites / join / knock | Invite cards, join and knock/request states | No invite/join UI | None | Missing |
| Room details | Room identity, members, notifications and settings | No room details UI | None | Missing |
| User profile | Profile, avatar and DM actions | No user profile UI | None | Missing |
| Roles / moderation | Member roles and authorised moderation actions | No moderation UI | None | Missing |
| Calls | MatrixRTC/Element Call entry, ringing and in-call states | No calling UI | None | Missing |
| Login / FTUE | Homeserver/authentication and first-run flows | No authentication UI | None | Missing |
| Verification / secure backup | Verification, recovery and backup flows | No security onboarding UI | None | Missing |
| Lock screen | PIN/biometric lock state | No lock screen | None | Missing |
| Preferences / appearance | User preferences including appearance/language/notifications | Theme can be forced by test/app constructor only | design-token tests | Foundation |
| Security & privacy | Sessions, privacy, recovery and account security | No settings UI | None | Missing |
| Licenses / about | App/legal information | No about/licenses UI | None | Missing |
| Error / offline states | Deliberate loading, empty, error and connectivity states | Deterministic adapters exist; user-visible states are not complete | deterministic adapter tests where applicable | Foundation |
| Adaptive phone layout | Mobile composition appropriate to width/orientation | Explicit portrait/landscape compact layout | `test/adaptive_layout_test.dart`, gallery goldens | Partial |
| Tablet / desktop layout | Wider composition without stretched phone UI | Two-pane layout with bounded 320-360 px sidebar | `test/adaptive_layout_test.dart`, gallery goldens | Partial |
| Reduced motion | Motion follows accessibility preference | Token durations collapse for `disableAnimations`/`accessibleNavigation`, and route transitions are removed when the platform requests disabled animations; current UI has no bespoke animated journey yet | `test/design_tokens_test.dart` | Foundation |

This matrix is a tracking artifact, not a parity claim. A row moves to `Pass` only when behavior, edge states, accessibility, goldens and the performance contract all meet the roadmap definition of parity.

## Manual major-UI side-by-side checklist

For each review, record the exact upstream commit or public reference image and the exact Kite golden/render. Review the rendered output, not only widget/source structure.

- [x] Home / room list — initial review recorded above; visual gaps remain.
- [ ] DM timeline.
- [ ] Group-room timeline.
- [ ] Composer / rich text.
- [x] Message actions / reactions — reviewed 2026-09-16 against current `develop`; gaps recorded above.
- [x] Threads — reviewed 2026-09-16 against current `develop`; gaps recorded above.
- [ ] Spaces.
- [ ] Room creation / invite.
- [ ] Room / user details.
- [ ] Settings / security.
- [ ] Poll / location / media.
- [ ] Incoming / outgoing / in-call.
- [ ] Empty / loading / error / offline states.
- [ ] Light / dark / true-black themes.
- [ ] Typography hierarchy.
- [ ] Spacing / radius / icon-size consistency.
- [ ] Avatar / image quality.
- [ ] Motion / easing at normal speed and frame-by-frame.

## Current-upstream scope audit

Audit established from a clean shallow checkout on 2026-09-14 and rechecked against the current Element X Android `develop` head on 2026-09-16.

- `develop` now points at `3e861cc64645a286a5455e0b47032b1a25b2f49d`, committed 2026-09-15. This is newer than the roadmap's original 2026-09-14 audit reference. This pass rechecked the current tree and refreshed the rendered Threads and message-action/reaction references; the commit itself is test-tooling-only (`Do not report detekt LargeClass issues on test classes (#7713)`), so it does not add a new user-facing parity requirement.
- The release-notes head in this tree is `v26.09.2`. Its parity-relevant changes include moving Knock and gallery-message sending into Labs; `v26.09.1` added multi-select poll creation/responses, and `v26.08.3` enabled user status. Those capabilities are tracked by the existing room/join, media/poll, and profile/parity rows rather than by adding duplicate roadmap criteria.
- Current Labs flags are `Threads`, `SendGalleryMessages`, and `Knock`; all default to disabled and remain unfinished. Threads stays a Kite requirement because the roadmap explicitly targets Threads 2.x. Knock/gallery behaviour is compared against its current upstream exposure instead of being treated as generally available UI.
- Other unfinished disabled flags include multi-account, QR login, black theme, jump-to-unread, room thread list, automatic back-pagination, selectable media quality, and message search. The current `FeatureFlags.MessageSearch` implementation remains disabled and unfinished; it is not treated as a generally available in-room-search parity blocker.
- The upstream tree contains first-party store screenshots plus the generated UI snapshot gallery (`screenshots/` and `tests/uitests/src/test/snapshots/images/`), including day/night home, call, room-creation, Labs and timeline states. These are the mechanical visual reference source when a public marketing screenshot is unavailable.
- No on-device voice-transcription implementation or feature module is present in the current `develop` tree. Matrix Classic-only or proposal-only capabilities remain outside the parity baseline until Element X ships them generally.
- This audit does not relax existing Kite roadmap requirements. Features already represented in the parity matrix remain required even when they are currently behind an upstream Labs/developer flag where the roadmap explicitly calls for current-upstream behaviour.

## Review discipline

A review is complete only when both reference and Kite renders are available for the same state. Golden changes are reviewed as product changes; broad updates are never accepted merely to make tests pass. Missing Element X screens remain visible as `Missing` in the matrix instead of being silently excluded from parity.
