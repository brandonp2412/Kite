package io.element.android.libraries.matrix.ui.media

import coil3.request.Options
import io.element.android.libraries.matrix.ui.media.animated.allowAnimatedImageDecoding

internal fun MediaRequestData.toKey(options: Options): String? {
    val previewVersion = if (kind is MediaRequestData.Kind.VideoThumbnail) "_validated-v2" else ""
    return source?.let { "${it.safeUrl}_${kind}_${options.allowAnimatedImageDecoding()}$previewVersion" }
}
