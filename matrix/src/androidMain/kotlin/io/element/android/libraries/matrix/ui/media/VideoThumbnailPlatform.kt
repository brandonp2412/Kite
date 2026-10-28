package io.element.android.libraries.matrix.ui.media

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import timber.log.Timber
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.roundToInt

/** Extract a small still frame from a fully downloaded, decrypted video. */
internal object VideoThumbnailPlatform {
    fun extractFrame(file: File): ByteArray? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            val frame = retriever.getFrameAtTime(500_000L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: retriever.getFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: return null
            try {
                val scale = minOf(1f, 800f / frame.width, 600f / frame.height)
                val scaled = if (scale < 1f) {
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
                    ByteArrayOutputStream().use { stream ->
                        if (scaled.compress(Bitmap.CompressFormat.JPEG, 82, stream)) {
                            stream.toByteArray()
                        } else {
                            null
                        }
                    }
                } finally {
                    if (scaled !== frame) scaled.recycle()
                }
            } finally {
                frame.recycle()
            }
        } catch (error: Exception) {
            Timber.w(error, "Failed to extract Android video preview")
            null
        } finally {
            retriever.release()
        }
    }
}
