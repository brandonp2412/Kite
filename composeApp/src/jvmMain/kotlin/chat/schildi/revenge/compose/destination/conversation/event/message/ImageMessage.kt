package chat.schildi.revenge.compose.destination.conversation.event.message

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
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
import kotlin.math.min

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
    val captionedTimelineImage = hasCaption && LocalMessageRenderContext.current == MessageRenderContext.NORMAL
    var displayAspectRatio by remember(source, width, height) {
        mutableFloatStateOf(aspectRatioOrNull(width, height) ?: 1f)
    }
    MessageBubble(
        isOwn = isOwn,
        timestamp = timestamp,
        modifier = if (captionedTimelineImage) modifier.width(captionMediaWidth(displayAspectRatio)) else modifier,
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
            displayAspectRatio = if (captionedTimelineImage) displayAspectRatio else null,
            onDecodedAspectRatio = if (captionedTimelineImage) { ratio -> displayAspectRatio = ratio } else null,
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
    displayAspectRatio: Float? = null,
    onDecodedAspectRatio: ((Float) -> Unit)? = null,
    onCaptionTextLayout: (TextLayoutResult?) -> Unit = {},
    overlay: @Composable () -> Unit = {},
) {
    // Preserve stable sizing for media without captions. Captioned images can
    // correct missing or inaccurate metadata once decoded so text fits the photo.
    val reservedAspectRatio = displayAspectRatio ?: aspectRatioOrNull(width, height) ?: 1f
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
        // Keep placeholders and overlays inside the reserved viewport.
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
                is AsyncImagePainter.State.Success -> {
                    if (onDecodedAspectRatio != null) {
                        val size = painter.intrinsicSize
                        LaunchedEffect(size) {
                            if (size.width.isFinite() && size.height.isFinite() &&
                                size.width > 0f && size.height > 0f
                            ) onDecodedAspectRatio(size.width / size.height)
                        }
                    }
                    SubcomposeAsyncImageContent(
                        modifier = Modifier.fillMaxSize().clip(FittedImageShape(painter.intrinsicSize, shape)),
                    )
                }
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

/** Keeps rounded corners on the *visible* ContentScale.Fit image when its reserved
 * viewport has a different aspect ratio (especially older outgoing media without info). */
internal class FittedImageShape(private val imageSize: Size, private val corners: Shape) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val rect = fittedMediaRect(size, imageSize)
        val child = corners.createOutline(rect.size, layoutDirection, density)
        if (rect.left == 0f && rect.top == 0f && rect.size == size) return child
        val path = Path()
        when (child) {
            is Outline.Rectangle -> path.addRect(rect)
            is Outline.Rounded -> {
                val rounded = child.roundRect
                path.addRoundRect(RoundRect(
                    left = rect.left, top = rect.top, right = rect.right, bottom = rect.bottom,
                    topLeftCornerRadius = rounded.topLeftCornerRadius,
                    topRightCornerRadius = rounded.topRightCornerRadius,
                    bottomRightCornerRadius = rounded.bottomRightCornerRadius,
                    bottomLeftCornerRadius = rounded.bottomLeftCornerRadius,
                ))
            }
            is Outline.Generic -> path.addPath(child.path, Offset(rect.left, rect.top))
        }
        return Outline.Generic(path)
    }
}

internal fun fittedMediaRect(viewport: Size, image: Size): Rect {
    if (!image.width.isFinite() || !image.height.isFinite() ||
        image.width <= 0f || image.height <= 0f || viewport.width <= 0f || viewport.height <= 0f
    ) return Rect(Offset.Zero, viewport)
    val scale = min(viewport.width / image.width, viewport.height / image.height)
    val width = image.width * scale
    val height = image.height * scale
    return Rect(Offset((viewport.width - width) / 2f, (viewport.height - height) / 2f), Size(width, height))
}

// One shared width for the caption and the visible picture. Media info can be
// absent or inaccurate; the decoded aspect ratio corrects it when available.
internal fun captionMediaWidth(aspectRatio: Float): Dp {
    val ratio = aspectRatio.takeIf { it.isFinite() && it > 0f } ?: 1f
    return (220.dp * ratio).coerceIn(Dimens.Conversation.imageMinWidth, 320.dp)
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
