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
