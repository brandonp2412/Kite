package chat.schildi.revenge.util

import io.element.android.libraries.matrix.api.timeline.InMemoryMediaThumbnail
import java.io.File

data class MediaMeasures(
    val width: Int?,
    val height: Int?,
    val durationMs: Long?,
)

/** Normalizes decoded image bounds to their displayed orientation, rejecting invalid decodes. */
internal fun imageMeasuresFromBounds(width: Int, height: Int, swapAxes: Boolean): MediaMeasures {
    if (width <= 0 || height <= 0) return MediaMeasures(null, null, null)
    return if (swapAxes) MediaMeasures(height, width, null) else MediaMeasures(width, height, null)
}

data class GeneratedVideoThumbnail(
    val thumbnail: InMemoryMediaThumbnail,
    val videoMeasures: MediaMeasures,
    val thumbnailMeasures: MediaMeasures,
)

/**
 * Utilities to probe basic media measures for local files.
 */
expect object MediaInfoUtil {
    fun probeImage(file: File): MediaMeasures
    fun probeImage(bytes: ByteArray): MediaMeasures
    fun generateImageBlurHash(file: File): String?
    fun generateImageBlurHash(bytes: ByteArray): String?
    fun generateVideoThumbnail(file: File): GeneratedVideoThumbnail?
    fun probeAudio(file: File): MediaMeasures
}
