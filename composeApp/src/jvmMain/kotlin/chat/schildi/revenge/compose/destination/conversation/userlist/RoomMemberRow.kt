package chat.schildi.revenge.compose.destination.conversation.userlist

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import chat.schildi.revenge.model.userlist.RoomMemberItem
import chat.schildi.revenge.model.userlist.RoomMemberListViewModel
import chat.schildi.revenge.plaintext.RoomMembershipFormat
import chat.schildi.revenge.plaintext.UserRoleFormat
import io.element.android.libraries.matrix.api.room.RoomMember.Role
import io.element.android.libraries.matrix.api.room.RoomMembershipState

@Composable
fun RoomMemberRow(
    roomMember: RoomMemberItem,
    viewModel: RoomMemberListViewModel,
    modifier: Modifier = Modifier,
) {
    UserListRow(
        item = roomMember,
        viewModel = viewModel,
        modifier = modifier,
    ) {
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            if (roomMember.value.role != Role.User) {
                RoomMemberBadge(
                    UserRoleFormat.formatUserRoleWithPowerLevel(
                        roomMember.value.role,
                        roomMember.value.powerLevel.takeIf { it != Long.MAX_VALUE },
                    ).render(),
                )
            }
            if (roomMember.value.membership != RoomMembershipState.JOIN) {
                RoomMemberBadge(
                    RoomMembershipFormat.formatRoomMembership(roomMember.value.membership).render(),
                )
            }
        }
    }
}

@Composable
private fun RoomMemberBadge(text: String) {
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHighest,
        tonalElevation = 0.dp,
    ) {
        Text(
            text = text,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
