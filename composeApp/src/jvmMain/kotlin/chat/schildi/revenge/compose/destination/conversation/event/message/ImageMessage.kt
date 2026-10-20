package chat.schildi.revenge.compose.destination.conversation.event.message

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import chat.schildi.lib.preferences.ScPrefs
import chat.schildi.revenge.preferences.value
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.compose.media.BlurHashPlaceholder
import chat.schildi.revenge.compose.media.rememberAnimatedImageTransform
import chat.schildi.revenge.compose.media.imageLoader
import chat.schildi.revenge.compose.media.onAsyncImageState
import coil3.compose.AsyncImagePainter
import chat.schildi.revenge.model.conversation.MessageMetadata
import coil3.compose.SubcomposeAsyncImage
import coil3.compose.SubcomposeAsyncImageContent
import com.beeper.android.messageformat.MatrixBodyParseResult
import io.element.android.libraries.matrix.api.media.MediaSource
import io.element.android.libraries.matrix.api.timeline.item.EventThreadInfo
import io.element.android.libraries.matrix.api.timeline.item.event.ImageLikeMessageType
import io.element.android.libraries.matrix.api.timeline.item.event.InReplyTo
import io.element.android.libraries.matrix.ui.media.MediaRequestData

@Composable
fun ImageMessage(
    image: ImageLikeMessageType,
    messageMetadata: MessageMetadata?,
    isOwn: Boolean,
    timestamp: TimestampOverlayContent?,
    inReplyTo: InReplyTo?,
    threadInfo: EventThreadInfo?,
    modifier: Modifier = Modifier,
) {
    ImageMessage(
        source = image.source,
        blurhash = image.info?.blurhash,
        width = image.info?.width,
        height = image.info?.height,
        messageMetadata = messageMetadata,
        isOwn = isOwn,
        timestamp = timestamp,
        inReplyTo = inReplyTo,
        threadInfo = threadInfo,
        modifier = modifier,
    )
}

@Composable
fun ImageMessage(
    source: MediaSource,
    blurhash: String? = null,
    width: Long? = null,
    height: Long? = null,
    messageMetadata: MessageMetadata?,
    isOwn: Boolean,
    timestamp: TimestampOverlayContent?,
    inReplyTo: InReplyTo?,
    threadInfo: EventThreadInfo?,
    modifier: Modifier = Modifier,
) {
    val hasCaption = messageMetadata?.preFormattedContent != null
    val isTransparent = !hasCaption && inReplyTo == null
    // Portrait attachments with a caption should remain compact and
    // right-aligned, matching the image width rather than the whole row.
    val captionWidth = if (hasCaption && (aspectRatioOrNull(width, height) ?: 1f) < 0.8f) 220.dp else 320.dp
    MessageBubble(
        isOwn = isOwn,
        timestamp = timestamp,
        modifier = if (hasCaption) modifier.widthIn(max = captionWidth) else modifier,
        padding = PaddingValues(Dimens.Conversation.imageBubbleInnerPadding),
        contentTextLayoutResult = null,
        isMediaOverlay = !isTransparent,
        transparent = isTransparent,
        allowTimestampOverlay = messageMetadata?.preFormattedContent?.allowTimestampOverlay() != false,
    ) {
        inReplyTo?.let {
            ReplyContent(
                it,
                threadInfo,
                Modifier.padding(Dimens.Conversation.messageBubbleInnerPadding),
            )
        }
        val shape = if (inReplyTo == null && messageMetadata?.preFormattedContent == null) {
            LocalMessageBubbleShape.current
        } else {
            val topRadius = 0.dp
            val bottomRadius = Dimens.Conversation.messageBubbleCornerRadius
            RoundedCornerShape(
                topStart = topRadius,
                topEnd = topRadius,
                bottomStart = bottomRadius,
                bottomEnd = bottomRadius,
            )
        }
        ImageMessageContent(
            model = MediaRequestData(source, MediaRequestData.Kind.Content),
            blurhash = blurhash,
            width = width,
            height = height,
            minWidth = Dimens.Conversation.imageMinWidth,
            minHeight = Dimens.Conversation.imageMinHeight,
            maxWidth = Dimens.Conversation.imageMaxWidth,
            maxHeight = when (LocalMessageRenderContext.current) {
                MessageRenderContext.NORMAL -> Dp.Infinity
                MessageRenderContext.IN_REPLY_TO -> Dimens.Conversation.imageRepliedToMaxHeight
            },
            caption = messageMetadata?.preFormattedContent,
            shape = shape,
            onCaptionTextLayout = {}
        )
    }
}

@Composable
fun ColumnScope.ImageMessageContent(
    model: Any,
    blurhash: String? = null,
    width: Long? = null,
    height: Long? = null,
    minWidth: Dp,
    minHeight: Dp,
    maxWidth: Dp,
    maxHeight: Dp,
    caption: MatrixBodyParseResult? = null,
    shape: Shape = Dimens.Conversation.messageBubbleShape,
    onCaptionTextLayout: (TextLayoutResult?) -> Unit = {},
    overlay: @Composable () -> Unit = {},
) {
    // Reserve identical bounds before and after decoding. Coil's intrinsic image
    // size can differ from the event metadata, and switching ratios on success
    // otherwise remeasures the whole message list as an image comes into view.
    // Unknown dimensions use a stable square rather than jumping after loading.
    val reservedAspectRatio = aspectRatioOrNull(width, height) ?: 1f
    if (caption != null) {
        TextLikeMessageContent(
            caption,
            allowBigEmojiOnly = false,
            modifier = Modifier.padding(Dimens.Conversation.messageBubblePadding),
            onTextLayout = onCaptionTextLayout,
        )
    } else {
        LaunchedEffect(Unit) { onCaptionTextLayout(null) }
    }
    Box(
        // Clip the entire media viewport, including Coil's subcomposed content,
        // so sent and received images retain identical rounded corners.
        modifier = Modifier.align(Alignment.CenterHorizontally).clip(shape),
        contentAlignment = Alignment.Center,
    ) {
        SubcomposeAsyncImage(
            model = model,
            contentDescription = null,
            imageLoader = imageLoader(),
            onState = ::onAsyncImageState,
            transform = rememberAnimatedImageTransform(),
            filterQuality = FilterQuality.High,
            contentScale = ContentScale.Fit,
            modifier = Modifier
                .then(
                    if (caption != null && LocalMessageRenderContext.current == MessageRenderContext.NORMAL) {
                        // Text + image share one width; don't letterbox a narrow portrait
                        // inside a much wider caption bubble.
                        Modifier.fillMaxWidth().aspectRatio(reservedAspectRatio)
                    } else {
                        Modifier.boundedMediaSize(minWidth, minHeight, maxWidth, maxHeight, reservedAspectRatio)
                    }
                ),
        ) {
            if (blurhash != null && ScPrefs.FORCE_RENDER_BLURHASH.value()) {
                BlurHashPlaceholder(
                    blurHash = blurhash,
                    width = width,
                    height = height,
                    modifier = Modifier.fillMaxSize(),
                )
                return@SubcomposeAsyncImage
            }
            when (painter.state.collectAsState().value) {
                is AsyncImagePainter.State.Success -> SubcomposeAsyncImageContent(
                    modifier = Modifier.fillMaxSize(),
                )
                AsyncImagePainter.State.Empty,
                is AsyncImagePainter.State.Loading,
                is AsyncImagePainter.State.Error -> {
                    BlurHashPlaceholder(
                        blurHash = blurhash,
                        width = width,
                        height = height,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
            }
        }
        overlay()
    }
}

private fun aspectRatioOrNull(width: Long?, height: Long?): Float? {
    val safeWidth = width?.takeIf { it > 0 } ?: return null
    val safeHeight = height?.takeIf { it > 0 } ?: return null
    return safeWidth.toFloat() / safeHeight
}

private fun Modifier.boundedMediaSize(
    minWidth: Dp,
    minHeight: Dp,
    maxWidth: Dp,
    maxHeight: Dp,
    aspectRatio: Float? = null,
): Modifier = sizeIn(
    minWidth = minWidth,
    minHeight = minHeight,
    maxWidth = maxWidth,
    maxHeight = maxHeight,
).then(
    aspectRatio
        ?.takeIf { it.isFinite() && it > 0f }
        ?.let { Modifier.aspectRatio(it) }
        ?: Modifier,
)
