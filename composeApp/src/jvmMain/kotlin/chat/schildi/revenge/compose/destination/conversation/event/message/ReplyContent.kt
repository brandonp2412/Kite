package chat.schildi.revenge.compose.destination.conversation.event.message

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.shape.RoundedCornerShape
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.actions.LocalRoomContextSuggestionsProvider
import chat.schildi.revenge.compose.components.LocalSessionId
import chat.schildi.revenge.compose.destination.conversation.event.EventContentLayout
import chat.schildi.revenge.model.conversation.messageMetadata
import chat.schildi.theme.scExposures
import io.element.android.libraries.matrix.api.timeline.item.EventThreadInfo
import io.element.android.libraries.matrix.api.timeline.item.event.InReplyTo
import kotlinx.collections.immutable.persistentMapOf
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.reply_failed_to_load

@Composable
fun ReplyContent(
    inReplyTo: InReplyTo,
    threadInfo: EventThreadInfo?,
    modifier: Modifier = Modifier,
    composerPreview: Boolean = false,
) {
    // TODO jump to message action
    val containerModifier = modifier
        .padding(bottom = Dimens.Conversation.replyItemPadding)
        // A reply arrives first as a tiny skeleton and later gains its sender,
        // text, or thumbnail. Do not let that asynchronous replacement move
        // the surrounding text or any other messages in the timeline.
        .let { if (composerPreview) it else it.height(92.dp) }
        .let {
            if (composerPreview) {
                it.background(
                    MaterialTheme.colorScheme.surfaceContainerHighest,
                    Dimens.Conversation.replyContentShape,
                )
            } else {
                it
                    .border(1.dp, MaterialTheme.scExposures.accentColor, Dimens.Conversation.replyContentShape)
                    .background(MaterialTheme.colorScheme.surfaceVariant, Dimens.Conversation.replyContentShape)
            }
        }
        .clip(Dimens.Conversation.replyContentShape)
    Box(containerModifier) {
        when (inReplyTo) {
            is InReplyTo.Error -> {
                Text(
                    stringResource(Res.string.reply_failed_to_load)
                )
            }
            is InReplyTo.Pending,
            is InReplyTo.NotLoaded -> {
                Box(
                    Modifier
                        .padding(horizontal = 12.dp, vertical = 10.dp)
                        .width(72.dp)
                        .height(10.dp)
                        .background(
                            MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.12f),
                            RoundedCornerShape(5.dp),
                        )
                )
            }
            is InReplyTo.Ready -> {
                val roomContext = LocalRoomContextSuggestionsProvider.current
                CompositionLocalProvider(
                    LocalMessageRenderContext provides MessageRenderContext.IN_REPLY_TO,
                    LocalThreadReplyContext provides
                            (threadInfo as? EventThreadInfo.ThreadResponse)
                                ?.threadRootId
                                ?.takeIf { it != roomContext?.threadId }
                                ?.let { threadId ->
                                    roomContext ?: return@let null
                                    ThreadReplyContext(
                                        sessionId = roomContext.sessionId,
                                        roomId = roomContext.roomId,
                                        threadId = threadId,
                                    )
                                }
                ) {
                    EventContentLayout(
                        eventId = inReplyTo.eventId,
                        content = inReplyTo.content,
                        messageMetadata = inReplyTo.content.messageMetadata(),
                        senderId = inReplyTo.senderId,
                        senderProfile = inReplyTo.senderProfile,
                        inReplyTo = null, // No recursive reply lookups please
                        threadInfo = null, // Again no recursion here
                        isOwn = inReplyTo.senderId.value == LocalSessionId.current?.value,
                        showSenderDetails = true,
                        roomMembersById = persistentMapOf(),
                        timestamp = null,
                        isSameAsPreviousSender = false,
                        isSameAsNextSender = false,
                    )
                }
            }
        }
    }
}
