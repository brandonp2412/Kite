package chat.schildi.revenge.compose.destination.conversation.event.message

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.ui.draw.alpha
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import chat.schildi.revenge.DateTimeFormat
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.compose.components.WithTooltip
import chat.schildi.revenge.compose.components.thenIf
import chat.schildi.theme.scExposures
import io.element.android.libraries.matrix.api.timeline.item.event.EventCanBeEdited
import io.element.android.libraries.matrix.api.timeline.item.event.EventTimelineItem
import io.element.android.libraries.matrix.api.timeline.item.event.LocalEventSendState
import io.element.android.libraries.matrix.api.timeline.item.event.RedactedContent
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.hint_sending
import shire.res.generated.resources.message_edited_decoration
import shire.res.generated.resources.send_error_invalid_mime_type
import shire.res.generated.resources.send_error_missing_media_content
import shire.res.generated.resources.send_error_sending_from_unverified_device
import shire.res.generated.resources.send_error_unknown
import shire.res.generated.resources.send_error_verified_user_changed_identity
import shire.res.generated.resources.send_error_verified_user_has_unsigned_device
import kotlin.math.max

internal val LocalMessageBubbleShape = staticCompositionLocalOf<Shape> {
    Dimens.Conversation.messageBubbleShape
}

internal val LocalStableTextLayoutObserver = staticCompositionLocalOf<((TextLayoutResult) -> Unit)?> { null }

private class StableTextLayoutHolder(var result: TextLayoutResult? = null)

data class TimestampOverlayContent(
    val timestamp: String,
    val isEdited: Boolean,
    val isSending: Boolean,
    val sendError: LocalEventSendState.Failed?,
)

fun EventTimelineItem.timestampOverlayContent() = TimestampOverlayContent(
    timestamp = DateTimeFormat.formatTime(DateTimeFormat.timestampToDateTime(timestamp)),
    isEdited = (content as? EventCanBeEdited)?.isEdited == true,
    isSending = localSendState is LocalEventSendState.Sending,
    sendError = localSendState as? LocalEventSendState.Failed,
)

@Composable
fun MessageBubble(
    isOwn: Boolean,
    timestamp: TimestampOverlayContent?,
    contentTextLayoutResult: TextLayoutResult? = null,
    allowTimestampOverlay: Boolean = true,
    isMediaOverlay: Boolean = false,
    modifier: Modifier = Modifier,
    padding: PaddingValues = Dimens.Conversation.messageBubblePadding,
    outlined: Boolean = false,
    transparent: Boolean = false,
    verticalArrangement: Arrangement.Vertical = Arrangement.Top,
    nonTextWidth: Dp = 0.dp,
    stableTextHeight: Boolean = false,
    stableTextLayoutKey: Any? = null,
    content: @Composable ColumnScope.() -> Unit
) {
    // Bypass double message bubble when nested in a reply
    if (LocalMessageRenderContext.current == MessageRenderContext.IN_REPLY_TO) {
        Column(modifier.padding(padding), verticalArrangement = verticalArrangement, content = content)
    } else {
        val color = if (transparent)
            Color.Transparent
        else if (isOwn)
            MaterialTheme.scExposures.bubbleBgOutgoing
        else
            MaterialTheme.scExposures.bubbleBgIncoming
        val bubbleShape = LocalMessageBubbleShape.current
        Box(
            modifier
                .then(
                    if (outlined) {
                        Modifier.border(
                            width = 1.dp,
                            color = color,
                            shape = bubbleShape,
                        )
                    } else {
                        Modifier.background(
                            color = color,
                            shape = bubbleShape,
                        )
                    }
                )
                .padding(padding),
        ) {
            if (stableTextHeight) {
                // Measure the body at full width. Capture its final line during the
                // same measure pass, before placing the always-reserved status slot.
                val reserveTimestamp = reservedTextTimestampInset(isOwn, timestamp) > 0.dp
                val density = LocalDensity.current
                val horizontalGap = with(density) { Dimens.Conversation.timestampHorizontalPaddingToText.roundToPx() }
                val verticalGap = with(density) { Dimens.Conversation.timestampVerticalMarginToText.roundToPx() }
                val measuredText = remember(stableTextLayoutKey) { StableTextLayoutHolder() }
                val textObserver = remember(measuredText) {
                    { result: TextLayoutResult -> measuredText.result = result }
                }
                Layout(content = {
                    CompositionLocalProvider(LocalStableTextLayoutObserver provides textObserver) {
                        Column(verticalArrangement = verticalArrangement, content = content)
                    }
                    if (reserveTimestamp) {
                        TimestampContent(timestamp, reserveSendingSpace = isOwn, withBackground = false)
                    }
                }) { children, constraints ->
                    val body = children.first().measure(constraints.copy(minWidth = 0, minHeight = 0))
                    val status = children.getOrNull(1)?.measure(constraints.copy(minWidth = 0, minHeight = 0))
                    if (status == null) {
                        layout(body.width, body.height) { body.place(0, 0) }
                    } else {
                        val position = stableTextTimestampPlacement(
                            contentWidth = body.width,
                            contentHeight = body.height,
                            lastLineRight = measuredText.result?.lastLineRightIncludingPlaceholders(),
                            statusWidth = status.width,
                            statusHeight = status.height,
                            maxWidth = constraints.maxWidth,
                            horizontalGap = horizontalGap,
                            verticalGap = verticalGap,
                        )
                        layout(position.width, position.height) {
                            body.place(0, 0)
                            status.place(position.statusX, position.statusY)
                        }
                    }
                }
            } else TimestampOverlayLayout(
                contentTextLayoutResult = contentTextLayoutResult,
                allowTimestampOverlay = allowTimestampOverlay,
                horizontalPadding = Dimens.Conversation.timestampHorizontalPaddingToText,
                verticalPadding = Dimens.Conversation.timestampVerticalMarginToText,
                nonTextWidth = nonTextWidth,
                content = {
                    Column(verticalArrangement = verticalArrangement, content = content)
                },
                overlay = {
                    TimestampContent(
                        content = timestamp,
                        reserveSendingSpace = isOwn,
                        withBackground = contentTextLayoutResult == null && isMediaOverlay,
                        modifier = Modifier.thenIf(isMediaOverlay && contentTextLayoutResult != null) {
                            padding(Dimens.Conversation.messageBubbleInnerPadding)
                        }
                    )
                }
            )
        }
    }
}

internal data class StableTextTimestampPlacement(
    val width: Int,
    val height: Int,
    val statusX: Int,
    val statusY: Int,
)

internal fun stableTextTimestampPlacement(
    contentWidth: Int,
    contentHeight: Int,
    lastLineRight: Int?,
    statusWidth: Int,
    statusHeight: Int,
    maxWidth: Int,
    horizontalGap: Int,
    verticalGap: Int,
): StableTextTimestampPlacement {
    val requiredWidth = lastLineRight?.plus(statusWidth + horizontalGap)
    if (requiredWidth != null && requiredWidth <= maxWidth) {
        val width = max(contentWidth, requiredWidth)
        return StableTextTimestampPlacement(
            width, max(contentHeight, statusHeight), width - statusWidth,
            (contentHeight - statusHeight).coerceAtLeast(0),
        )
    }
    val width = max(contentWidth, statusWidth)
    return StableTextTimestampPlacement(
        width, contentHeight + verticalGap + statusHeight,
        width - statusWidth, contentHeight + verticalGap,
    )
}

/**
 * Fixed before measuring body text. A delivery-state update may change the
 * decoration inside the slot, but cannot change line wrapping or row height.
 */
internal fun reservedTextTimestampInset(
    isOwn: Boolean,
    timestamp: TimestampOverlayContent?,
): Dp = when {
    timestamp == null -> 0.dp
    timestamp.isEdited -> 116.dp
    isOwn || timestamp.isSending || timestamp.sendError != null -> 76.dp
    else -> 0.dp
}

@Composable
private fun TimestampContent(
    content: TimestampOverlayContent?,
    reserveSendingSpace: Boolean,
    withBackground: Boolean,
    modifier: Modifier = Modifier,
) {
    if (content == null) return

    // Google Messages keeps successful message bubbles free of an always-visible time stamp.
    // Preserve only message state that actually needs attention (edited/sending/failed)
    // and include the time alongside that state.
    val hasStatusDecoration = content.isEdited ||
            content.isSending ||
            content.sendError != null
    if (!hasStatusDecoration && !reserveSendingSpace) return

    val overlayBgColor = MaterialTheme.scExposures.timestampOverlayBg
    Row(
        modifier.thenIf(withBackground) {
            background(
                overlayBgColor,
                Dimens.Conversation.timestampOverlayShape,
            ).padding(Dimens.Conversation.timestampPaddingWithOverlayBg)
        }.alpha(if (hasStatusDecoration) 1f else 0f),
        horizontalArrangement = Dimens.horizontalArrangementSmall,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val textColor = if (withBackground)
            MaterialTheme.scExposures.timestampOverlayFgOnBg
        else
            MaterialTheme.colorScheme.onSurfaceVariant
        if (content.isEdited) {
            Text(
                stringResource(Res.string.message_edited_decoration),
                color = textColor,
                style = Dimens.Conversation.messageTimestampStyle,
                modifier = Modifier.alignByBaseline(),
            )
        }
        // A single predetermined slot handles sending, failed and sent states.
        // The failed icon must never append extra width and rewrap the bubble.
        if (reserveSendingSpace || content.isSending || content.sendError != null) {
            Box(Modifier.size(Dimens.Conversation.timestampDecorationIcon)) {
                if (content.sendError != null) {
                    val errorText: String = when (content.sendError) {
                        is LocalEventSendState.Failed.InvalidMimeType -> stringResource(Res.string.send_error_invalid_mime_type)
                        LocalEventSendState.Failed.MissingMediaContent -> stringResource(Res.string.send_error_missing_media_content)
                        LocalEventSendState.Failed.SendingFromUnverifiedDevice -> stringResource(Res.string.send_error_sending_from_unverified_device)
                        is LocalEventSendState.Failed.Unknown -> stringResource(Res.string.send_error_unknown)
                        is LocalEventSendState.Failed.VerifiedUserChangedIdentity -> stringResource(Res.string.send_error_verified_user_changed_identity)
                        is LocalEventSendState.Failed.VerifiedUserHasUnsignedDevice -> stringResource(Res.string.send_error_verified_user_has_unsigned_device)
                    }
                    WithTooltip(errorText) {
                        Icon(
                            Icons.Default.ErrorOutline,
                            errorText,
                            tint = MaterialTheme.colorScheme.error,
                            modifier = Modifier.size(Dimens.Conversation.timestampDecorationIcon),
                        )
                    }
                } else {
                    Icon(
                        Icons.Default.AccessTime,
                        stringResource(Res.string.hint_sending),
                        tint = textColor,
                        modifier = Modifier.size(Dimens.Conversation.timestampDecorationIcon)
                            .alpha(if (content.isSending) 1f else 0f),
                    )
                }
            }
        }
        Text(
            content.timestamp,
            color = textColor,
            style = Dimens.Conversation.messageTimestampStyle,
            modifier = Modifier.alignByBaseline(),
        )
    }
}
