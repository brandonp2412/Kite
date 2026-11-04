package chat.schildi.revenge.compose.destination.conversation.event.message

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import chat.schildi.revenge.Dimens
import chat.schildi.theme.LocalMessageStyle

@Composable
fun MessageLayout(
    isOwn: Boolean,
    showSenderDetails: Boolean,
    joinsPreviousBubble: Boolean,
    joinsNextBubble: Boolean,
    modifier: Modifier = Modifier,
    messageContentModifier: Modifier = Modifier,
    senderAvatar: @Composable () -> Unit,
    senderName: @Composable () -> Unit,
    messageContent: @Composable () -> Unit,
    selectionIndicator: (@Composable () -> Unit)? = null,
) {
    when (LocalMessageRenderContext.current) {
        MessageRenderContext.NORMAL -> {
            MessageLayoutNormal(
                isOwn = isOwn,
                showSenderDetails = showSenderDetails,
                joinsPreviousBubble = joinsPreviousBubble,
                joinsNextBubble = joinsNextBubble,
                modifier = modifier,
                messageContentModifier = messageContentModifier,
                senderAvatar = senderAvatar,
                senderName = senderName,
                messageContent = messageContent,
                selectionIndicator = selectionIndicator,
            )
        }
        MessageRenderContext.IN_REPLY_TO -> {
            MessageLayoutInReplyTo(
                senderName = senderName,
                messageContent = messageContent,
                modifier = modifier,
                messageContentModifier = messageContentModifier,
            )
        }
    }
}

@Composable
fun MessageLayoutNormal(
    isOwn: Boolean,
    showSenderDetails: Boolean,
    joinsPreviousBubble: Boolean,
    joinsNextBubble: Boolean,
    modifier: Modifier = Modifier,
    messageContentModifier: Modifier = Modifier,
    senderAvatar: @Composable () -> Unit,
    senderName: @Composable () -> Unit,
    messageContent: @Composable () -> Unit,
    selectionIndicator: (@Composable () -> Unit)? = null,
) {
    val mainLayoutDirection = LocalLayoutDirection.current
    val thisLayoutDirection = if (isOwn) {
        if (mainLayoutDirection == LayoutDirection.Ltr)
            LayoutDirection.Rtl
        else
            LayoutDirection.Ltr
    } else {
        mainLayoutDirection
    }
    val bubbleShape = remember(isOwn, joinsPreviousBubble, joinsNextBubble) {
        Dimens.Conversation.messageBubbleShape(
            isOwn = isOwn,
            joinsPrevious = joinsPreviousBubble,
            joinsNext = joinsNextBubble,
        )
    }
    CompositionLocalProvider(
        LocalLayoutDirection provides thisLayoutDirection,
        LocalMessageBubbleShape provides bubbleShape,
    ) {
        Row(
            modifier.fillMaxWidth()
        ) {
            val messageStyle = LocalMessageStyle.current
            if (!isOwn) {
                // Reserve a stable leading slot, including in direct rooms without avatars.
                // Selection replaces its content without moving the message bubble.
                BoxWithDirection(
                    mainLayoutDirection,
                    Modifier
                        .align(if (selectionIndicator != null) Alignment.CenterVertically else Alignment.Top)
                        .padding(end = Dimens.Conversation.avatarItemPadding)
                        .width(messageStyle.avatarSize)
                ) {
                    if (selectionIndicator != null) {
                        selectionIndicator()
                    } else if (showSenderDetails) {
                        senderAvatar()
                    }
                }
            }
            Column(
                Modifier
                    .padding(
                        end = if (isOwn || !showSenderDetails) {
                            messageStyle.otherSideMarginOutgoing
                        } else {
                            messageStyle.otherSideMargin
                        },
                    )
                    .widthIn(max = messageStyle.maxWidth),
            ) {
                Column(Modifier.fillMaxWidth()) {
                    if (!isOwn && showSenderDetails) {
                        BoxWithDirection(mainLayoutDirection) {
                            senderName()
                        }
                    }
                    BoxWithDirection(mainLayoutDirection, messageContentModifier) {
                        messageContent()
                    }
                }
            }
        }
    }
}

@Composable
fun MessageLayoutInReplyTo(
    senderName: @Composable () -> Unit,
    messageContent: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    messageContentModifier: Modifier = Modifier,
) {
    Column(modifier) {
        Box(
            Modifier
                .padding(
                    start = Dimens.Conversation.messageBubbleInnerPadding,
                    end = Dimens.Conversation.messageBubbleInnerPadding,
                    top = Dimens.Conversation.messageBubbleInnerPadding,
                )
        ) {
            senderName()
        }
        Box(messageContentModifier) {
            messageContent()
        }
    }
}

@Composable
private fun BoxWithDirection(
    direction: LayoutDirection,
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    Box(modifier) {
        CompositionLocalProvider(
            LocalLayoutDirection provides direction,
        ) {
            content()
        }
    }
}
