package chat.schildi.revenge.compose.media

import co.touchlab.kermit.Logger
import coil3.compose.AsyncImagePainter

fun onAsyncImageError(error: AsyncImagePainter.State.Error) {
    // The Coil state includes encrypted Matrix media keys in the request model.
    // Never log the full state or exception message.
    Logger.withTag("AsyncImage").w(
        "Failed to load image: " + error.result.throwable.javaClass.simpleName
    )
}

fun onAsyncImageState(state: AsyncImagePainter.State) {
    if (state is AsyncImagePainter.State.Error) {
        onAsyncImageError(state)
    }
}
