package chat.schildi.revenge.compose.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import chat.schildi.lib.preferences.ScPrefs
import chat.schildi.revenge.preferences.value
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.compose.media.rememberAnimatedImageTransform
import chat.schildi.revenge.compose.media.imageLoader
import chat.schildi.revenge.compose.media.NetworkIconColorRepository
import chat.schildi.revenge.compose.media.NetworkIconColorState
import chat.schildi.revenge.compose.media.compositeOver
import chat.schildi.revenge.compose.media.contrastRatio
import coil3.compose.AsyncImagePainter
import coil3.compose.LocalPlatformContext
import coil3.compose.SubcomposeAsyncImage
import coil3.compose.SubcomposeAsyncImageContent
import coil3.request.ImageRequest
import io.element.android.libraries.matrix.api.core.SessionId
import io.element.android.libraries.matrix.api.media.MediaSource
import io.element.android.libraries.matrix.ui.media.MediaRequestData
import io.element.android.libraries.matrix.ui.media.animated.allowAnimatedImageDecoding

private const val NETWORK_FALLBACK_ALPHA = 0.5f

@Composable
fun AvatarImage(
    source: MediaSource?,
    size: Dp,
    displayName: String,
    modifier: Modifier = Modifier,
    fallbackColorSource: MediaSource? = null,
    sessionId: SessionId? = LocalSessionId.current,
    shape: Shape = Dimens.avatarShape,
    contentDescription: String? = null,
    allowAnimated: Boolean = ScPrefs.ANIMATE_AVATARS.value(),
) {
    if (source == null || source.safeUrl.isEmpty()) {
        AvatarFallback(displayName, shape, size, fallbackColorSource = fallbackColorSource, sessionId = sessionId)
        return
    }
    // Model doesn't appear different enough from adding the option to invalidate on setting toggle, so key it
    key(allowAnimated) {
        val context = LocalPlatformContext.current
        val model = remember(source, allowAnimated, context) {
            ImageRequest.Builder(context)
                .data(MediaRequestData(source, MediaRequestData.Kind.Content))
                .allowAnimatedImageDecoding(allowAnimated)
                .build()
        }
        SubcomposeAsyncImage(
            modifier = modifier.size(size).clip(shape),
            imageLoader = imageLoader(sessionId),
            model = model,
            transform = rememberAnimatedImageTransform(),
            contentScale = ContentScale.Crop,
            alignment = Alignment.Center,
            contentDescription = contentDescription,
        ) {
            val painterState = painter.state.collectAsState().value
            val loaded = painterState is AsyncImagePainter.State.Success
            // Keep the same size and fallback in place while an asynchronously
            // decoded image is revealed. Replacing initials with a photo in one
            // frame was particularly noticeable when opening a conversation.
            val imageAlpha = animateFloatAsState(
                targetValue = if (loaded) 1f else 0f,
                animationSpec = tween(90),
                label = "Avatar reveal",
            ).value
            Box(Modifier.size(size), contentAlignment = Alignment.Center) {
                if (!loaded || imageAlpha < 1f) {
                    AvatarFallback(
                        displayName = displayName,
                        shape = shape,
                        size = size,
                        fallbackColorSource = fallbackColorSource,
                        sessionId = sessionId,
                        isError = painterState is AsyncImagePainter.State.Error,
                    )
                }
                if (loaded) {
                    this@SubcomposeAsyncImage.SubcomposeAsyncImageContent(Modifier.fillMaxSize().alpha(imageAlpha))
                }
            }
        }
    }
}

fun String.firstCodePoint(index: Int = 0): String? {
    if (isEmpty()) return null
    val cp = codePointAt(index)
    val count = Character.charCount(cp)
    return substring(index, index + count)
}

@Composable
fun AvatarFallback(
    displayName: String,
    shape: Shape,
    size: Dp,
    modifier: Modifier = Modifier,
    fallbackColorSource: MediaSource? = null,
    sessionId: SessionId? = LocalSessionId.current,
    isError: Boolean = false,
) {
    val stateColor = if (ScPrefs.RENDER_AVATAR_STATES.value()) animateColorAsState(
        if (isError) {
            MaterialTheme.colorScheme.error.copy(alpha = 0.5f)
        } else {
            MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
        }
    ).value else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
    val networkColor = if (fallbackColorSource == null) {
        null
    } else {
        val state = NetworkIconColorRepository.colorFor(
            source = fallbackColorSource,
            imageLoader = imageLoader(sessionId),
            platformContext = LocalPlatformContext.current,
        ).collectAsState().value
        (state as? NetworkIconColorState.Available)?.color
    }
    val color = networkColor?.copy(alpha = NETWORK_FALLBACK_ALPHA) ?: stateColor
    val contrastBackground = color.compositeOver(MaterialTheme.colorScheme.surface)
    Box(modifier.size(size).background(color, shape), contentAlignment = Alignment.Center) {
        val text = remember(displayName) {
            val cleanedName = displayName.removePrefix("@")
            val firstChar = cleanedName.firstCodePoint() ?: "?"
            val firstNonAlphaNum = cleanedName.indexOfFirst { !it.isLetterOrDigit() }
            val secondChar = if (firstNonAlphaNum != -1)
                cleanedName.substring(firstNonAlphaNum).firstOrNull { it.isLetterOrDigit() }
            else
                null
            if (secondChar == null) {
                firstChar
            } else {
                "$firstChar$secondChar"
            }
        }
        val textSize = LocalDensity.current.run {
            (size/2).toSp()
        }
        Text(
            text,
            color = MaterialTheme.colorScheme.run {
                if (onSurface.contrastRatio(contrastBackground) >= inverseOnSurface.contrastRatio(contrastBackground)) onSurface else inverseOnSurface
            },
            style = MaterialTheme.typography.headlineSmall.copy(fontSize = textSize, lineHeight = textSize),
            maxLines = 1,
        )
    }
}
