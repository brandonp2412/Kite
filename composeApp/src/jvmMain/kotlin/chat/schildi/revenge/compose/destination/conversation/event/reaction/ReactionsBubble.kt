package chat.schildi.revenge.compose.destination.conversation.event.reaction

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import kotlinx.coroutines.delay
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.actions.FocusRole
import chat.schildi.revenge.actions.InteractionAction
import chat.schildi.revenge.actions.actionProvider
import chat.schildi.revenge.actions.plainTextCopyAction
import chat.schildi.revenge.compose.components.LocalSessionId
import chat.schildi.revenge.compose.components.UserTimestampItem
import chat.schildi.revenge.compose.components.WithUserTimestampListPopup
import chat.schildi.revenge.compose.focus.keyFocusable
import chat.schildi.revenge.compose.focus.rememberFocusId
import chat.schildi.revenge.model.conversation.ConversationViewModel
import io.element.android.libraries.matrix.api.core.UserId
import io.element.android.libraries.matrix.api.room.RoomMember
import io.element.android.libraries.matrix.api.timeline.item.event.EventOrTransactionId
import io.element.android.libraries.matrix.api.timeline.item.event.EventReaction
import kotlinx.collections.immutable.ImmutableMap
import kotlinx.collections.immutable.toImmutableList

@Composable
fun ReactionsBubble(
    viewModel: ConversationViewModel,
    eventOrTransactionId: EventOrTransactionId,
    reaction: EventReaction,
    present: Boolean,
    roomMembersById: ImmutableMap<UserId, RoomMember>,
    modifier: Modifier = Modifier
) {
    val focusId = rememberFocusId()
    val userTimestamps = remember(reaction, roomMembersById) {
        reaction.senders.map { sender ->
            val member = roomMembersById[sender.senderId]
            UserTimestampItem(
                userId = sender.senderId,
                displayName = member?.displayName,
                avatarUrl = member?.avatarUrl,
                timestamp = sender.timestamp,
                extra = reaction.key,
            )
        }.toImmutableList()
    }
    val includesSelf = reaction.senders.any { it.senderId == LocalSessionId.current }
    // The SDK only updates reaction senders after a remote toggle completes.
    // Show the local removal immediately; reconcile when the timeline updates.
    var pendingSelf by remember(eventOrTransactionId, reaction.key) { mutableStateOf<Boolean?>(null) }
    val visibleSelf = pendingSelf ?: includesSelf
    val count = reaction.senders.size + (if (visibleSelf) 1 else 0) - (if (includesSelf) 1 else 0)
    LaunchedEffect(includesSelf, pendingSelf) {
        if (pendingSelf == includesSelf) pendingSelf = null
    }
    LaunchedEffect(pendingSelf) {
        if (pendingSelf != null) {
            delay(5_000)
            pendingSelf = null // Roll back UI if sending failed or the server never acknowledged it.
        }
    }
    AnimatedVisibility(
        visible = present && count > 0,
        enter = fadeIn(tween(140)) + expandHorizontally(tween(140)),
        exit = fadeOut(tween(180)) + shrinkHorizontally(tween(180)),
    ) {
    WithUserTimestampListPopup(
        focusId = focusId,
        users = userTimestamps,
        modifier = modifier,
        tooltipPrefix = reaction.shortcode?.plus(" ") ?: "",
        leadingItemContent = {
            ReactionContent(
                reaction.key,
                reaction.shortcode,
                MaterialTheme.typography.headlineSmall,
                modifier = LocalDensity.current.run {
                    // Popup content needs explicit width to avoid intrinsic width crash
                    Modifier.size(MaterialTheme.typography.headlineSmall.lineHeight.toDp())
                },
            )
        }
    ) {
        Row(
            modifier.let {
                if (visibleSelf) {
                    it.background(
                        MaterialTheme.colorScheme.primaryContainer,
                        Dimens.Conversation.reactionShape,
                    )
                        .border(
                            1.dp,
                            MaterialTheme.colorScheme.primary,
                            Dimens.Conversation.reactionShape,
                        )
                } else {
                    it.background(MaterialTheme.colorScheme.surfaceContainerHigh, Dimens.Conversation.reactionShape)
                }
            }
                .clip(Dimens.Conversation.reactionShape)
                .keyFocusable(
                    id = focusId,
                    role = FocusRole.NESTED_AUX_ITEM,
                    actionProvider = actionProvider(
                        primaryAction = InteractionAction.Invoke {
                            val submitted = viewModel.toggleReaction(eventOrTransactionId, reaction.key)
                            if (submitted) pendingSelf = !visibleSelf
                            submitted
                        },
                        secondaryAction = InteractionAction.ContextMenu(focusId, null),
                        copyActions = plainTextCopyAction { reaction.key },
                    ),
                )
                .padding(
                    horizontal = Dimens.Conversation.reactionInnerPaddingHorizontal,
                    vertical = Dimens.Conversation.reactionInnerPaddingVertical,
                ),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            ReactionContent(reaction.key, reaction.shortcode)
            Text(
                count.coerceAtLeast(1).toString(),
                color = if (visibleSelf) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface,
                style = MaterialTheme.typography.labelMedium,
            )
        }
    }
    }
}
