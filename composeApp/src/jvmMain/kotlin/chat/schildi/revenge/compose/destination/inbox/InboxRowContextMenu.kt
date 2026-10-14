package chat.schildi.revenge.compose.destination.inbox

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.LowPriority
import androidx.compose.material.icons.filled.MeetingRoom
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.input.key.Key
import chat.schildi.revenge.compose.components.ContextMenuActionEntry
import chat.schildi.revenge.compose.components.ContextMenuDecoration
import chat.schildi.revenge.compose.components.ContextMenuEntry
import chat.schildi.revenge.compose.components.isAllowed
import chat.schildi.resources.toStringHolder
import chat.schildi.revenge.config.keybindings.Action
import chat.schildi.revenge.config.keybindings.ActionRoomNotificationSetting
import chat.schildi.revenge.model.PendingAction
import chat.schildi.revenge.model.ScopedRoomSummary
import io.element.android.libraries.matrix.api.room.RoomNotificationMode
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toPersistentList
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_context_low_priority_toggle
import shire.res.generated.resources.action_join
import shire.res.generated.resources.action_leave
import shire.res.generated.resources.action_reject_invite
import shire.res.generated.resources.action_mute
import shire.res.generated.resources.action_pin
import shire.res.generated.resources.action_unmute
import shire.res.generated.resources.action_unpin

@Composable
fun ScopedRoomSummary.contextMenu(): ImmutableList<ContextMenuEntry> {
    return if (summary.isInvite()) {
        listOfNotNull(
            ContextMenuActionEntry(
                Res.string.action_join.toStringHolder(),
                rememberVectorPainter(Icons.Default.MeetingRoom),
                Action.Room.Join,
                enabled = PendingAction.RoomJoin(summary.roomId).isAllowed(),
                keyboardShortcut = Key.J,
            ),
            ContextMenuActionEntry(
                Res.string.action_reject_invite.toStringHolder(),
                rememberVectorPainter(Icons.Default.MeetingRoom),
                Action.Room.Leave,
                critical = true,
                enabled = PendingAction.RoomLeave(summary.roomId).isAllowed(),
                keyboardShortcut = Key.R,
            ),
        ).toPersistentList()
    } else {
        val notificationMode = summary.info.userDefinedNotificationMode
        val isMuted = notificationMode == RoomNotificationMode.MENTIONS_AND_KEYWORDS_ONLY ||
                notificationMode == RoomNotificationMode.MUTE
        listOfNotNull(
            ContextMenuActionEntry(
                if (summary.info.isFavorite) {
                    Res.string.action_unpin.toStringHolder()
                } else {
                    Res.string.action_pin.toStringHolder()
                },
                rememberVectorPainter(Icons.Default.PushPin),
                Action.Room.MarkFavorite,
                persistentListOf((!summary.info.isFavorite).toString()),
                decoration = ContextMenuDecoration.Toggle(summary.info.isFavorite),
                keyboardShortcut = Key.F,
            ),
            ContextMenuActionEntry(
                Res.string.action_context_low_priority_toggle.toStringHolder(),
                rememberVectorPainter(Icons.Default.LowPriority),
                Action.Room.MarkLowPriority,
                persistentListOf((!summary.info.isLowPriority).toString()),
                decoration = ContextMenuDecoration.Toggle(summary.info.isLowPriority),
                keyboardShortcut = Key.L,
            ).takeIf { !summary.info.isFavorite },
            ContextMenuActionEntry(
                if (isMuted) {
                    Res.string.action_unmute.toStringHolder()
                } else {
                    Res.string.action_mute.toStringHolder()
                },
                rememberVectorPainter(Icons.Default.NotificationsOff),
                Action.Room.SetRoomNotifications,
                actionArgs = persistentListOf(
                    if (isMuted) {
                        ActionRoomNotificationSetting.All.name
                    } else {
                        ActionRoomNotificationSetting.Mentions.name
                    },
                ),
                keyboardShortcut = Key.M,
            ),
            ContextMenuActionEntry(
                Res.string.action_leave.toStringHolder(),
                rememberVectorPainter(Icons.Default.MeetingRoom),
                Action.Room.Leave,
                critical = true,
                enabled = PendingAction.RoomLeave(summary.roomId).isAllowed(),
                keyboardShortcut = Key.V,
            ),
        ).toPersistentList()
    }
}
