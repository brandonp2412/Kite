package chat.schildi.revenge.util

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import io.element.android.libraries.matrix.api.timeline.InMemoryMediaThumbnail
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.roundToInt

actual object MediaInfoUtil {
    actual fun probeImage(file: File) = MediaMeasures(null, null, null)
    actual fun probeImage(bytes: ByteArray) = MediaMeasures(null, null, null)
    actual fun generateImageBlurHash(file: File): String? = null
    actual fun generateImageBlurHash(bytes: ByteArray): String? = null

    actual fun generateVideoThumbnail(file: File): GeneratedVideoThumbnail? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()
            val metadataWidth = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull()
            val metadataHeight = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull()
            val frame = retriever.getFrameAtTime(500_000L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: retriever.getFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: return null
            try {
                val scale = minOf(1f, 800f / frame.width, 600f / frame.height)
                val resized = if (scale < 1f) {
                    Bitmap.createScaledBitmap(
                        frame,
                        (frame.width * scale).roundToInt().coerceAtLeast(1),
                        (frame.height * scale).roundToInt().coerceAtLeast(1),
                        true,
                    )
                } else {
                    frame
                }
                try {
                    val jpeg = ByteArrayOutputStream().use { output ->
                        if (!resized.compress(Bitmap.CompressFormat.JPEG, 82, output)) return null
                        output.toByteArray()
                    }
                    GeneratedVideoThumbnail(
                        thumbnail = InMemoryMediaThumbnail(
                            data = jpeg,
                            filename = file.nameWithoutExtension + "-thumbnail.jpg",
                            mimeType = "image/jpeg",
                        ),
                        videoMeasures = MediaMeasures(
                            width = metadataWidth ?: frame.width,
                            height = metadataHeight ?: frame.height,
                            durationMs = durationMs,
                        ),
                        thumbnailMeasures = MediaMeasures(
                            width = resized.width,
                            height = resized.height,
                            durationMs = null,
                        ),
                    )
                } finally {
                    if (resized !== frame) resized.recycle()
                }
            } finally {
                frame.recycle()
            }
        } catch (_: Exception) {
            null
        } finally {
            retriever.release()
        }
    }

    actual fun probeAudio(file: File) = MediaMeasures(null, null, null)
}
