# Kite current Element X parity audit

Reference: `element-hq/element-x-android` `develop` at `ba80abcbf0f5238940fea9b7a6b22f7a8bc518ac`, resolved on 2026-09-15.

This document records capability-level parity evidence that is broader than the rendered comparison in `VISUAL_PARITY.md`. A reviewed gap remains a gap: the corresponding ROADMAP parity checkbox stays open until Kite implements the capability or records an intentional product difference.

## Settings entry audit

The current Element X preferences root, advanced settings, notification settings, About, Labs, Analytics, and developer settings sources were re-read at the reference SHA. The table accounts for every user-facing entry exposed by those settings surfaces; conditional entries are listed even when a server, feature flag, or platform capability can hide them.

| Element X setting / entry | Current Kite capability | Status / owner |
| --- | --- | --- |
| Own profile header / edit profile | `user_profile_controller.dart` provides profile foundations, but Kite has no equivalent settings/profile screen in the current shell. | Gap — M10 |
| User status | No current settings surface. | Gap — M10 |
| Multi-account switcher / add account | Account/session foundations exist, but no settings switcher UI is exposed. | Gap — M1/M10 |
| Notifications | `NotificationSettingsScreen` exists with account master toggle, categories, per-room mode, message sound, and call ringtone. | Partial — M10/M11 |
| Screen lock | `AppLockController` covers PIN, biometrics, and hidden notification contents; no current settings screen exposes the flow. | Foundation only — M2/M10 |
| Encryption / secure backup | Encryption recovery/trust controllers exist; no settings entry currently exposes full recovery/backup UX. | Foundation only — M2 |
| Manage account and devices | Session-device/account management controllers exist; no current settings page exposes the complete flow. | Foundation only — M10 |
| Link new device | Verification foundations exist, but no settings entry exposes the Element X flow. | Gap — M2/M10 |
| Blocked users | No current blocked-users settings UI. | Gap — M10 |
| Advanced settings | `GeneralSettingsScreen` covers appearance and language only; Element X advanced settings contain additional entries below. | Partial — M10 |
| Labs | No Kite Labs settings screen. Current upstream Labs/flag scope remains tracked by the feature scan in `VISUAL_PARITY.md`. | Gap — M14 scope audit |
| About | `SupportSettingsScreen` shows version/build and open-source licenses. | Present, narrower than Element X legal-link set — M10/M16 |
| Report a problem | `SupportSettingsScreen` has a sanitised report flow. | Present — M10 |
| Analytics | No current analytics settings surface. | Gap — M10 |
| Sign out | Account-management foundation exists; no current root settings UI exposes the destructive action. | Foundation only — M10 |
| Delete/deactivate account | No current settings UI. | Gap — M10 |
| Developer options | No normal-user Matrix-complexity developer screen is exposed. This remains intentionally absent unless a genuinely useful Kite developer surface is justified. | Intentional pending M10 criterion |
| Appearance: system/light/dark/black | `GeneralSettingsScreen` exposes all four modes. | Present — M10; visual true-black implementation still separately open |
| Language | Kite exposes language selection, although full localisation/plural/date formatting is not complete. | Partial — M10/M12 |
| View source / developer-mode toggle | No equivalent user-facing advanced setting. | Gap — M10 |
| Share presence | No current settings control. | Gap — M10 |
| Media compression / image upload optimisation | No current setting. | Gap — M5/M10 |
| Video upload quality | No current setting. | Gap — M5/M10 |
| Hide invite avatars | No current moderation/safety setting. | Gap — M10 |
| Timeline media preview policy | No current setting. | Gap — M7/M10 |
| Live-location update distance / app permission shortcut | No current setting. | Gap — M5/M10 |
| Android app-notification/system permission state | Kite has an in-app master setting but no platform-settings status/permission entry. | Gap — M11 |
| Full-screen call-notification permission | No current settings entry. | Gap — M8/M11 |
| Group-chat default notification mode | Kite has category toggles and per-room modes, but no separate Element X-style group default. | Gap — M10 |
| Direct-chat default notification mode | Kite has category toggles and per-room modes, but no separate Element X-style DM default. | Gap — M10 |
| `@room` mention notifications | Kite has a general mentions category, not the same dedicated setting. | Partial — M10 |
| Invite notifications | No dedicated category in current `NotificationCategory`. | Gap — M10/M11 |
| Message notification sound | Exposed by `NotificationSettingsScreen`. | Present — M10 |
| Call ringtone | Exposed by `NotificationSettingsScreen`. | Present — M10 |
| Notification troubleshooting | No current troubleshooting entry. | Gap — M11 |
| Push provider selection | No current advanced notification entry. | Gap — M11 |
| About legal links | Kite exposes package licenses but not the full Element X legal-link set. | Gap — M16 |
| Open-source licenses | Exposed by `SupportSettingsScreen`. | Present — M10/M16 |

### Settings audit conclusion

The settings inventory is current and no entry is silently omitted from the parity plan, but the Milestone 14 “every Element X settings entry” checkbox remains open because multiple entries are still gaps rather than implemented capabilities or approved intentional differences. The highest-value missing surfaces are a real settings root, profile/account/device management, app-lock/encryption entry points, notification defaults/troubleshooting, and the remaining advanced media/privacy controls.

## Room-list action audit

The current `RoomListEvent.kt` and `RoomListMenuAction.kt` at the reference SHA were read exhaustively. State-only events such as visible-range updates and banner dismissal are included where they correspond to user-visible room-list behaviour.

| Element X room-list action | Current Kite capability | Status / owner |
| --- | --- | --- |
| Search/results toggle | Room-list search/filter benchmark surfaces exist, but the production Home header has no search entry yet. | Gap — M3 |
| Show/hide room context menu | No room-row context menu is exposed by current `HomeScreen`. | Gap — M3/M10 |
| Accept invite | Invite membership foundations exist outside Home; no room-list invite action is rendered. | Gap — M9 |
| Decline invite / decline-and-block menu | No equivalent room-list flow. | Gap — M9/M10 |
| Leave room, optionally confirmed | Room membership mutation foundation supports leave, but Home exposes no room-row action. | Foundation only — M9 |
| Mark as read | No room-list action. | Gap — M3 |
| Mark as unread | No room-list action. | Gap — M3 |
| Favourite / unfavourite room | Deterministic fixtures model favourite state, but current Home has no mutation action. | Gap — M3 |
| Verification/banner dismissal | Verification foundations exist, but Home has no equivalent prompt/banner flow. | Gap — M2/M3 |
| New-notification-sound banner dismissal | No corresponding Home banner. | Gap — M10/M11 |
| Invite friends menu action | No Home overflow/menu action. | Gap — M3/M9 |
| Report bug menu action | Support settings provide problem reporting, but not from the Home menu. | Partial — M10 |

This completes the current-upstream room-list action inventory; it intentionally does not claim capability parity. Each missing action remains scheduled by the owning milestone above.

## Message action audit

`TimelineItemAction.kt` at the reference SHA defines the complete current action enum, and `MessagesEvent.kt` adds reaction toggling plus live-location and room-read actions. Kite's current action sheet and TalkBack custom actions expose Reply, Copy text, Edit, and Remove only.

| Element X message action / event | Current Kite capability | Status / owner |
| --- | --- | --- |
| View in timeline | Deep-link/focus foundations exist; no message action is exposed. | Gap — M4/M11 |
| Forward | No current message action. | Gap — M4 |
| Copy text | Implemented in action sheet and TalkBack actions. | Present — M4/M12 |
| Copy caption | Media-caption messages expose a dedicated Copy caption action backed by the existing exact-text clipboard path. | Present — M5 |
| Copy link | No current message action. | Gap — M4 |
| Remove/redact | Implemented for own messages with confirmation. | Present — M4 |
| Reply | Implemented in composer context and TalkBack actions. | Present — M4 |
| Reply in thread | The message action sheet and accessibility actions open a dedicated thread from any non-redacted event; the first runtime reply promotes a previously unthreaded event into timeline/thread-list thread state. | Present foundation — M6 |
| Edit message | Implemented for own text messages. | Present — M4 |
| Edit poll / End poll | Own active polls expose an explicit End poll action with fixed-geometry ending/final state. Poll editing is not implemented because the current deterministic boundary does not yet model an upstream-compatible edit transport. | Partial — M4/M5 |
| Edit / add / remove caption | No production media-caption mutation flow. | Gap — M5 |
| View source | No current message action. | Gap — M4/M10 |
| Report content | No current message action. | Gap — M4/M10 |
| Pin / unpin | No production pinned-message action. | Gap — M4 |
| Retry sending | Failed local sends expose a dedicated retry affordance rather than the action sheet. | Present, intentional placement difference — M4 |
| Toggle reaction | Reaction mutation benchmark foundations exist, but no production reaction picker/summary action is rendered. | Gap — M4 |
| User/profile click | Member/profile foundations exist; current timeline sender chrome is not actionable. | Gap — M4/M10 |
| Show/stop live-location share | The composer now exposes fixed and live location actions with stable preview/loading/permission states, starts live sharing through an SDK-ready location port, and gives own active live-location cards a fixed-geometry Stop action with in-place progress/ended state. Real platform geolocation/permission adapters and Matrix transport are still required. | Present foundation — M5 |
| Mark fully read and exit | No equivalent room/timeline action. | Gap — M3/M4 |

This completes the current-upstream message-action inventory while retaining every unimplemented action as a visible parity gap.

## Timeline event-type audit

The sealed `TimelineItemEventContent` family, its concrete model files, the virtual timeline models, and grouped-event wrapper were enumerated at the reference SHA. Kite's production `TimelineMessage` currently models text, replies, edit/redaction state, local send state, static/live location payloads, and poll question/choice/result state; the mixed-event benchmark surface is deliberately synthetic and is not counted as production support beyond those concrete event models.

| Element X timeline type | Current Kite capability | Status / owner |
| --- | --- | --- |
| Text / formatted text / emote / notice | Plain text is rendered; production formatted/emote/notice variants are not distinct. | Partial — M4 |
| Image / video / audio / voice / file | Media viewer and media workflow foundations exist, but the production Home timeline model does not render these event types. | Gap — M5/M7 |
| Gallery / multi-attachment | No production timeline event model. | Gap — M5/M7 |
| Sticker | No production timeline event model. | Gap — M5 |
| Poll | Production timeline messages now carry an SDK-ready poll payload and render fixed-height choice/result rows with explicit selected, ending and ended states. The composer creates 2–6 choice polls, vote changes mutate only the poll leaf signal, and own active polls can be ended. Deterministic light/dark goldens and 120 Hz geometry tests pass; real Matrix poll event mapping/interoperability and locked profile evidence remain unfinished. | Present foundation — M4/M5 |
| Static / live location | Production timeline messages carry an SDK-ready location payload and render a fixed-geometry map/location card with explicit static/live/ending/ended state. The composer has deterministic fixed/live location preparation, permission-denied/permanently-denied recovery, send, and stop workflows; live state changes mutate only the message location signal. Real platform geolocation/permission adapters and Matrix SDK event mapping/interoperability remain unfinished. | Present foundation — M4/M5 |
| Encrypted / undecryptable event | Encryption foundations exist, but there is no dedicated production timeline event state. | Gap — M2/M4 |
| Redacted event | Implemented for current text messages. | Present — M4 |
| Room-membership state event | Room membership foundations exist; no production timeline state-event renderer. | Gap — M4/M9 |
| Profile-change state event | No production timeline renderer. | Gap — M4/M10 |
| Generic state event | No production timeline renderer. | Gap — M4 |
| MatrixRTC notification | Call foundations are separate from the timeline; no production RTC timeline event. | Gap — M8 |
| Legacy call invite | No production timeline event. | Gap — M8 |
| Unknown/unsupported event | No explicit production unknown-event fallback row. | Gap — M4 |
| Thread root / thread response metadata | Thread summaries and dedicated thread view exist. | Partial — M6 |
| Reactions / read receipts / local-send state attached to events | Local-send state is rendered; mutation benchmark coverage exists for reactions/receipts, but production reaction/receipt UI remains incomplete. | Partial — M4 |
| Grouped events | No equivalent production grouped-event presentation. | Gap — M4 |
| Day separator | No production virtual item. | Gap — M4 |
| Read marker | No production virtual item. | Gap — M4 |
| Typing notification | Mutation benchmark foundation exists; no production virtual row/indicator in the current timeline. | Gap — M4 |
| Loading indicator / room-beginning marker | Pagination exists, but these production virtual timeline items are not rendered. | Gap — M4 |
| Last-forward indicator | No production virtual item. | Gap — M4 |

This completes the current-upstream timeline event-type inventory without treating synthetic benchmark shapes as shipped UI.

## Room and user moderation audit

The current moderation API exposes Display profile, Kick, Ban and Unban, while user-profile actions add Start DM, Block, Unblock, Withdraw verification and Copy. Room-level management adds leave, report, favourite/read state and room notification actions.

| Element X moderation/profile action | Current Kite capability | Status / owner |
| --- | --- | --- |
| Display member profile | User-profile controller/screen foundations exist and room members are selectable. | Present foundation — M9/M10 |
| Kick member | Permission-aware action and confirmation are implemented in `RoomMembersScreen`. | Present — M9 |
| Ban member | Permission-aware action and confirmation are implemented; mutation accepts a reason. | Present — M9 |
| Unban member | Permission-aware action and confirmation are implemented. | Present — M9 |
| Change member power level | Kite additionally exposes User/Moderator/Admin power-level mutations with authorization checks. | Present — M9 |
| Invite member | Permission-aware membership mutation exists. | Present foundation — M9 |
| Start DM from profile | Profile foundations exist; no complete production navigation flow is claimed. | Partial — M9/M10 |
| Block / unblock user | `UserProfileController` models and persists block state. | Present foundation — M10 |
| Withdraw verification | Verification foundations exist; profile action parity is incomplete. | Gap — M2/M10 |
| Copy user/profile identifier | No complete production profile action parity claimed. | Gap — M10 |
| Report room, optionally leave | Room mutation port supports report-with-reason and leave, but the production report-room flow is incomplete. | Foundation only — M9/M10 |
| Leave room | Room membership mutation foundation exists; production entry points remain incomplete. | Foundation only — M9 |
| Favourite / mark read / mark unread room | No complete production room-details actions. | Gap — M3/M9 |
| Mute / unmute and per-room notification mode | Notification settings foundations model per-room modes, but room-details parity is incomplete. | Partial — M10/M11 |

This completes the current-upstream room/user moderation action inventory; gaps remain explicitly owned by M2, M3, M9, M10 and M11.

## Notification and deep-link route audit

The current push stack, `PendingIntentFactory`, notification action factories, `DeeplinkData`, and app `IntentResolver` were read at the reference SHA. Element X notification navigation carries a session plus room and optional event/thread identity; external Matrix permalinks are resolved separately from notification deep links.

| Element X notification / route | Current Kite capability | Status / owner |
| --- | --- | --- |
| Open account/session root | Element X can open a session-level notification target. Kite notification destinations are room-scoped and have no root-notification target. | Gap — M11 |
| Message notification -> exact event | `NotificationDispatchCoordinator` maps message notifications to an account-aware room/event destination. | Present foundation — M11 |
| Mention notification -> exact event | Mention notifications use the same exact account/room/event route. | Present foundation — M11 |
| Thread notification -> exact reply/thread | Kite preserves account, room, reply event and thread-root IDs in `AppDestination.thread`. | Present foundation — M6/M11 |
| Invite notification -> room | Kite maps an invite to the account-aware room destination. | Present foundation — M3/M11 |
| Ringing-call notification -> call | `AppDestination.call` and `CallDeepLinkCoordinator` preserve account/room/call identity, but Matrix notification dispatch does not yet create call notifications and there is no production ringing screen. | Partial — M8/M11 |
| Notification quick reply | Element X has an event/thread-aware Android direct-reply action. Kite has no OS notification reply action. | Gap — M5/M11 |
| Mark room/thread read from notification | Element X exposes a thread-aware mark-read action. Kite clears matching notifications when a room/event is read in-app, but has no OS notification mark-read action. | Partial — M11 |
| Accept / reject invite from notification | Element X provides both notification actions. Kite has no OS invite action flow. | Gap — M9/M11 |
| Dismiss event / invite / room / summary | Element X has explicit dismiss intents. Kite has cancellation and read-reconciliation abstractions but not the complete OS notification lifecycle. | Partial — M11 |
| Correct account before navigation | Element X deep links carry `SessionId`; Kite destinations carry `accountId` and `NotificationCoordinator` activates it before navigation. | Present foundation — M1/M11 |
| External room/event/thread permalink | Element X resolves external Matrix permalinks separately from notification intents. Kite's deep-link routing foundation supports room, event and thread destinations. | Present foundation — M1/M11 |
| Call deep link | Kite has an explicit account-aware call target and coordinator. | Present foundation — M8/M11 |

This completes the current-upstream notification/deep-link route inventory. It does not close the notification milestone: push delivery, OS actions, ringing-call presentation and multi-account production integration remain explicit gaps.

## Call-flow audit

The current Element X call entry point, room-call state, incoming-call UI, call-screen state, ringing notification path and picture-in-picture state were reviewed at the reference SHA. Element X delegates media to Element Call while the Android client owns launch intent, ringing, lifecycle and PiP integration.

| Element X call flow | Current Kite capability | Status / owner |
| --- | --- | --- |
| Start 1:1 voice/video | `KiteCallCoordinator` exposes direct voice/video start and maps to Element Call-compatible launch intents. | Present foundation — M8 |
| Start / join group call | Group start and join are represented with explicit call ID and media kind. | Present foundation — M8 |
| Incoming ringing state | `registerIncomingCall` models ringing with exact room/call identity, but Kite has no production incoming-call UI. | Foundation only — M8 |
| Accept / decline / hang up | Coordinator and gateway boundaries cover all three operations with deterministic state transitions. | Present foundation — M8 |
| Microphone mute | Coordinator forwards mute state through the MatrixRTC gateway. | Present foundation — M8 |
| Camera enable / disable / switch | Video-only camera controls and camera-facing state are modelled. | Present foundation — M8 |
| Audio route selection | Available routes and explicit route selection are modelled. | Present foundation — M8 |
| Participant grid / spotlight | Participant and spotlight state exist, but there is no rendered participant UI. | Foundation only — M8 |
| Picture-in-picture | A platform PiP port and enter/exit/support state exist, but no production call screen is wired to it. | Foundation only — M8 |
| Background / locked continuation | Platform continuation capabilities and app-state handoff are modelled. | Present foundation — M8 |
| Audio interruption | Media interruption is explicitly forwarded to the gateway. | Present foundation — M8 |
| Transient reconnect | Reconnecting state and gateway retry are implemented. | Present foundation — M8 |
| Room active-call / timeline state | `KiteCallActivity` exposes call lifecycle state; production call timeline rendering remains missing. | Partial — M4/M8 |
| Custom ringtone | Notification settings expose a custom call-ringtone choice. | Present — M10 |
| Deep link into call | `CallDeepLinkCoordinator` activates the correct account before opening the call destination. | Present foundation — M8/M11 |
| E2EE call launch policy | Launch config requires per-participant E2EE, but release parity still depends on the audited MatrixRTC/Element Call integration rather than Kite crypto. | Foundation only — M8 |

This completes the current-upstream call-flow inventory. Rendering, incoming-call presentation, real MatrixRTC integration and call-transition performance remain open and prevent call parity from being claimed.

## Space and Thread flow audit

The current Home Space filters, Space root/add-room/leave/settings flows, Threads list, threaded-message node and thread top bar were reviewed at the reference SHA. Kite's current Spaces benchmark surface is synthetic and is not counted as shipped Space UI.

| Element X Space / Thread flow | Current Kite capability | Status / owner |
| --- | --- | --- |
| Show/select/clear Space filter | No production Space filter UI; benchmark-only coverage is not counted as capability. | Gap — M3 |
| Joined Spaces area | No production Spaces area. | Gap — M3 |
| Browse/paginate Space rooms | No production Space room browser. | Gap — M3 |
| Join room from Space | No production flow. | Gap — M3 |
| Accept / decline Space-room invite | No production flow. | Gap — M3 |
| Space topic viewer | No production flow. | Gap — M3 |
| Enter manage mode / select and remove rooms | No production Space management UI. | Gap — M3 |
| Add/search/select rooms in a Space | No production add-room flow. | Gap — M3 |
| Leave Space with room selection/retry | No production leave-Space flow. | Gap — M3 |
| Space settings | No production settings surface. | Gap — M3 |
| Timeline thread summary / open thread | Kite renders thread summaries and opens a dedicated thread route while preserving parent context. | Present foundation — M6 |
| Read/write thread replies | Dedicated thread replies, composer and send/retry state are implemented. | Present foundation — M6 |
| Thread pagination | Controller and UI load older replies with deduplication. | Present foundation — M6 |
| Thread follow/subscription state | Follow/unfollow state, in-flight state and failure state are implemented. | Present foundation — M6 |
| Thread unread/read state | Per-thread and room-level unread counts plus latest-read reply state are modelled. | Present foundation — M6 |
| Focus exact thread reply from route | Thread destination preserves root/reply identity and the thread view supports focused-reply state. | Present foundation — M6/M11 |
| Prevent unsupported live-location sharing in thread | Controller rejects the unsupported thread composer action explicitly. | Present foundation — M6 |
| Dedicated all-threads list / pagination | Kite now exposes a room-scoped Threads list with bounded presentation paging, root/latest-reply metadata, unread state, and thread round-trip navigation. Real SDK-backed thread-list pagination remains to be wired. | Present foundation — M6 |

This completes the current-upstream Space/Thread flow inventory while leaving the unimplemented Space UI and SDK-backed Threads-list pagination visible as parity gaps. Thread performance remains separately blocked by the strict Waydroid raster gate recorded in `PERFORMANCE.md`.
