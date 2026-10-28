package io.element.android.libraries.matrix.ui.media

import timber.log.Timber
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Desktop fallback uses ffmpeg, which Kite already supports for outgoing video previews. */
internal object VideoThumbnailPlatform {
    fun extractFrame(file: File): ByteArray? {
        val process = try {
            ProcessBuilder(
                "ffmpeg", "-v", "error",
                "-ss", "0.5",
                "-i", file.absolutePath,
                "-frames:v", "1",
                "-vf", "scale=800:600:force_original_aspect_ratio=decrease",
                "-f", "image2pipe", "-vcodec", "mjpeg", "pipe:1",
            ).redirectError(ProcessBuilder.Redirect.DISCARD).start()
        } catch (error: Exception) {
            Timber.w(error, "Unable to start ffmpeg for video preview")
            return null
        }
        val reader = Executors.newSingleThreadExecutor()
        return try {
            val future = reader.submit<ByteArray> {
                process.inputStream.use { it.readNBytes(2_000_001) }
            }
            val bytes = future.get(15, TimeUnit.SECONDS)
            if (bytes.isEmpty() || bytes.size > 2_000_000 ||
                !process.waitFor(2, TimeUnit.SECONDS) || process.exitValue() != 0
            ) {
                null
            } else {
                bytes
            }
        } catch (error: Exception) {
            Timber.w(error, "Failed to extract desktop video preview")
            null
        } finally {
            process.destroyForcibly()
            reader.shutdownNow()
        }
    }
}
