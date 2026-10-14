package chat.schildi.revenge.compose.destination.conversation.event.message

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
import chat.schildi.matrixsdk.urlpreview.UrlPreview
import chat.schildi.matrixsdk.urlpreview.UrlPreviewInfo
import chat.schildi.matrixsdk.urlpreview.UrlPreviewStateProvider
import chat.schildi.lib.preferences.ScPrefs
import chat.schildi.revenge.preferences.value
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.compose.components.thenIf
import chat.schildi.revenge.compose.media.rememberAnimatedImageTransform
import chat.schildi.revenge.compose.media.imageLoader
import chat.schildi.revenge.model.conversation.firstPreviewUrl
import chat.schildi.theme.LocalMessageStyle
import coil3.compose.AsyncImagePainter
import coil3.compose.SubcomposeAsyncImage
import coil3.compose.SubcomposeAsyncImageContent
import com.beeper.android.messageformat.MatrixBodyParseResult
import io.element.android.libraries.matrix.api.media.MediaSource
import io.element.android.libraries.matrix.ui.media.MediaRequestData

/**
 * Provides a [UrlPreviewStateProvider] to the composition.
 */
val LocalUrlPreviewStateProvider = staticCompositionLocalOf<UrlPreviewStateProvider?> { null }

@Composable
fun resolveUrlPreview(body: MatrixBodyParseResult): UrlPreviewInfo? {
    if (LocalMessageRenderContext.current == MessageRenderContext.IN_REPLY_TO) {
        return null
    }
    // This will be null when url previews are disabled for this room
    val urlPreviewStateProvider = LocalUrlPreviewStateProvider.current ?: return null
    // Whether to only preview links that explicitly contain "https://" at the beginning.
    val requireExplicitHttps = ScPrefs.URL_PREVIEWS_REQUIRE_EXPLICIT_LINKS.value()
    val previewUrl = body.firstPreviewUrl(requireExplicitHttps) ?: return null
    val previewStateHolder = remember(previewUrl, urlPreviewStateProvider) {
        urlPreviewStateProvider.getStateHolder(previewUrl)
    }
    return previewStateHolder.state.collectAsState().value?.let {
        UrlPreviewInfo(previewStateHolder.url, it)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun UrlPreviewView(
    urlPreview: UrlPreview,
    paddingValues: PaddingValues = PaddingValues(bottom = Dimens.Conversation.replyItemPadding),
    modifier: Modifier = Modifier,
    onLongCLick: (() -> Unit)? = null,
    onClick: () -> Unit,
) {
    if (LocalMessageRenderContext.current == MessageRenderContext.IN_REPLY_TO) {
        return
    }
    Column(
        modifier
            // Similar background design to InReplyToView
            .padding(paddingValues)
            .clip(Dimens.Conversation.UrlPreview.cardShape)
            .background(MaterialTheme.colorScheme.surface)
            .border(Dimens.Conversation.UrlPreview.cardBorderWidth, MaterialTheme.colorScheme.tertiary, Dimens.Conversation.UrlPreview.cardShape) // Add border so link previews look different from replies
            .combinedClickable(onClick = onClick, onLongClick = onLongCLick)
            .padding(Dimens.Conversation.UrlPreview.cardInnerPadding)
    ) {
        val density = LocalDensity.current
        val textStyle = LocalMessageStyle.current.textStyle
        Row {
            urlPreview.imageUrl?.let { imageUrl ->
                // The thumbnail must not resize when the image decodes or the title
                // is measured: either change would move adjacent chat messages.
                val reservedSize = fitImageSize(
                    urlPreview.imageWidth,
                    urlPreview.imageHeight,
                    density,
                )
                val thumbnailModifier = reservedSize?.let { size ->
                    with(density) { Modifier.size(size.width.toDp(), size.height.toDp()) }
                } ?: Modifier.size(
                    Dimens.Conversation.UrlPreview.imageMaxWidth,
                    Dimens.Conversation.UrlPreview.imageMinHeight,
                )
                SubcomposeAsyncImage(
                    modifier = Modifier.align(Alignment.Top),
                    imageLoader = imageLoader(),
                    model = MediaRequestData(MediaSource(imageUrl), MediaRequestData.Kind.Content),
                    transform = rememberAnimatedImageTransform(),
                    contentScale = ContentScale.Fit,
                    alignment = Alignment.Center,
                    contentDescription = null,
                ) {
                    val state = painter.state.collectAsState().value
                    val innerModifier = thumbnailModifier
                        .fillMaxSize()
                        .padding(Dimens.Conversation.UrlPreview.imagePadding)
                        .clip(Dimens.Conversation.UrlPreview.imageShape)
                    when (state) {
                        is AsyncImagePainter.State.Success -> SubcomposeAsyncImageContent(
                            modifier = innerModifier,
                        )
                        else -> Box(
                            modifier = innerModifier
                                .background(MaterialTheme.colorScheme.surfaceVariant),
                        )
                    }
                }
            }
            Column(
                Modifier
                    .padding(horizontal = Dimens.Conversation.UrlPreview.titlePaddingHorizontal)
                    .align(Alignment.CenterVertically),
            ) {
                urlPreview.title?.let { title ->
                    Text(
                        text = title.trim(),
                        style = textStyle,
                        color = MaterialTheme.colorScheme.secondary,
                        maxLines = 4,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                urlPreview.siteName?.let { site ->
                    Text(
                        text = site.trim(),
                        style = textStyle,
                        color = MaterialTheme.colorScheme.secondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
        urlPreview.description?.let { description ->
            val sanitized = description.replace("\n\n", "\n").replace("\n", " ").trim()
            var expanded by remember { mutableStateOf(false) }
            Text(
                text = sanitized,
                style = textStyle,
                color = MaterialTheme.colorScheme.secondary,
                maxLines = if (expanded) 50 else 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .thenIf(urlPreview.imageUrl != null || urlPreview.title != null || urlPreview.siteName != null) { padding(top = Dimens.Conversation.UrlPreview.descriptionTopPadding) }
                    .clip(Dimens.Conversation.UrlPreview.descriptionShape)
                    .combinedClickable(onLongClick = onLongCLick) { expanded = !expanded }
                    .padding(horizontal = Dimens.Conversation.UrlPreview.descriptionPaddingHorizontal),
            )
        }
    }
}

private fun fitImageSize(
    imageWidth: Int?,
    imageHeight: Int?,
    density: Density,
): Size? {
    val widthPx = imageWidth?.takeIf { it > 0 } ?: return null
    val heightPx = imageHeight?.takeIf { it > 0 } ?: return null
    val aspect = widthPx.toFloat() / heightPx
    val maxWidthPx = with(density) { Dimens.Conversation.UrlPreview.imageMaxWidth.toPx() }
    val maxHeightPx = with(density) { Dimens.Conversation.UrlPreview.imageMinHeight.toPx() }
    val minWidthPx = with(density) { Dimens.Conversation.UrlPreview.imageMinSize.toPx() }
    var width = maxWidthPx
    var height = width / aspect
    if (height > maxHeightPx) {
        height = maxHeightPx
        width = height * aspect
    }
    return Size(maxOf(width, minWidthPx), maxOf(height, minWidthPx))
}
