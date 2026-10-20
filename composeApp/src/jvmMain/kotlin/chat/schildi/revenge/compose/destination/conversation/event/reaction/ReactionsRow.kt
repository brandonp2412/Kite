package chat.schildi.revenge.compose.destination.conversation.event.reaction

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import kotlinx.coroutines.delay
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
fun ColumnScope.ReactionsRow(
    viewModel: ConversationViewModel,
    eventOrTransactionId: EventOrTransactionId,
    reactions: ImmutableList<EventReaction>,
    roomMembersById: ImmutableMap<UserId, RoomMember>,
    messageIsOwn: Boolean,
    showSenderDetails: Boolean,
    modifier: Modifier = Modifier,
) {
    val retainedReactions = remember(eventOrTransactionId) {
        mutableStateListOf<EventReaction>().apply { addAll(reactions) }
    }
    LaunchedEffect(reactions) {
        val activeKeys = reactions.mapTo(hashSetOf()) { it.key }
        reactions.forEach { updated ->
            val index = retainedReactions.indexOfFirst { it.key == updated.key }
            if (index >= 0) retainedReactions[index] = updated else retainedReactions.add(updated)
        }
        if (retainedReactions.any { it.key !in activeKeys }) {
            delay(220) // Let removed reactions finish their exit before the SDK drops their rows.
            retainedReactions.removeAll { it.key !in activeKeys }
        }
    }
    val alignment = if (messageIsOwn) Alignment.End else Alignment.Start
    // Keep the last reaction's layout alive while the entire reaction row
    // collapses vertically. Removing the FlowRow in a single frame jolts every
    // message above it in the reverse-layout timeline.
    AnimatedVisibility(
        visible = retainedReactions.isNotEmpty(),
        enter = fadeIn(tween(160)) + expandVertically(tween(220)),
        exit = fadeOut(tween(180)) + shrinkVertically(tween(240)),
        modifier = modifier.align(alignment),
    ) {
    FlowRow(
        modifier = Modifier
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
            alignment,
        ),
    ) {
        retainedReactions.forEach { reaction ->
            key(reaction.key) {
                ReactionsBubble(
                    viewModel, eventOrTransactionId, reaction,
                    present = reactions.any { it.key == reaction.key },
                    roomMembersById = roomMembersById,
                )
            }
        }
    }
    }
}
