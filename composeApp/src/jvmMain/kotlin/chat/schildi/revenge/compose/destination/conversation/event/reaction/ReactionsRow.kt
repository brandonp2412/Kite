package chat.schildi.revenge.compose.destination.conversation.event.reaction

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.model.conversation.ConversationViewModel
import chat.schildi.theme.LocalMessageStyle
import io.element.android.libraries.matrix.api.core.UserId
import io.element.android.libraries.matrix.api.room.RoomMember
import io.element.android.libraries.matrix.api.timeline.item.event.EventOrTransactionId
import io.element.android.libraries.matrix.api.timeline.item.event.EventReaction
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.ImmutableMap

@Composable
fun BoxScope.ReactionsRow(
    viewModel: ConversationViewModel,
    eventOrTransactionId: EventOrTransactionId,
    reactions: ImmutableList<EventReaction>,
    roomMembersById: ImmutableMap<UserId, RoomMember>,
    messageIsOwn: Boolean,
    showSenderDetails: Boolean,
    modifier: Modifier = Modifier,
) {
    if (reactions.isEmpty()) return
    val alignment = if (messageIsOwn) Alignment.BottomEnd else Alignment.BottomStart
    FlowRow(
        modifier = modifier
            .align(alignment)
            .offset(y = (-6).dp)
            .padding(
                top = Dimens.Conversation.reactionPaddingVertical,
                start = if (messageIsOwn)
                    LocalMessageStyle.current.otherSideMarginOutgoing
                else if (showSenderDetails)
                    LocalMessageStyle.current.avatarReservation
                else
                    0.dp,
                end = if (messageIsOwn)
                    0.dp
                else
                    LocalMessageStyle.current.otherSideMargin,
            ),
        verticalArrangement = Arrangement.spacedBy(Dimens.Conversation.reactionPaddingVertical),
        horizontalArrangement = Arrangement.spacedBy(
            Dimens.Conversation.reactionPaddingHorizontal,
            if (messageIsOwn) Alignment.End else Alignment.Start,
        ),
    ) {
        reactions.forEach { reaction ->
            key(reaction.key) {
                ReactionsBubble(viewModel, eventOrTransactionId, reaction, roomMembersById)
            }
        }
    }
}
