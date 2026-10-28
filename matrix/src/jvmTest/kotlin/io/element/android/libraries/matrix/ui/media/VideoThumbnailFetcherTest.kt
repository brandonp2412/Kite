package io.element.android.libraries.matrix.ui.media

import io.element.android.libraries.matrix.api.media.MatrixMediaLoader
import io.element.android.libraries.matrix.api.media.MediaFile
import io.element.android.libraries.matrix.api.media.MediaSource
import kotlinx.coroutines.runBlocking
import org.junit.Assume.assumeTrue
import java.awt.image.BufferedImage
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files
import java.util.concurrent.TimeUnit
import javax.imageio.ImageIO
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class VideoThumbnailFetcherTest {
    @Test
    fun uploadedThumbnailIsUsedAndCachedWithoutVideoDownload() = withTempDirectory { dir ->
        val loader = FakeMediaLoader(dir).apply { uploadedImage = jpeg() }
        val source = MediaSource("mxc://example.test/video")
        val request = MediaRequestData(
            source,
            MediaRequestData.Kind.VideoThumbnail(
                thumbnailSource = MediaSource("mxc://example.test/thumb"),
                mimeType = "video/mp4",
                sizeBytes = 100L,
            ),
        )

        assertNotNull(runBlocking { RevengeCoilMediaFetcher(loader, request).fetch() })
        assertNotNull(runBlocking { RevengeCoilMediaFetcher(loader, request).fetch() })
        assertEquals(1, loader.contentCalls)
        assertEquals(0, loader.thumbnailCalls)
        assertEquals(0, loader.downloadCalls)
        assertEquals(1, File(dir, "videoPreviews").listFiles()?.size)
    }

    @Test
    fun serverReturningNonImageBytesFallsBackToVideoFrameAndCachesIt() = withTempDirectory { dir ->
        assumeTrue("ffmpeg is required for desktop video thumbnails", hasFfmpeg())
        val video = syntheticVideo(dir)
        val loader = FakeMediaLoader(dir).apply {
            videoFile = video
            serverThumbnail = video.readBytes() // The Matrix endpoint reported success with MP4 bytes.
        }
        val request = MediaRequestData(
            MediaSource("mxc://example.test/video-without-thumb"),
            MediaRequestData.Kind.VideoThumbnail(null, "video/mp4", video.length()),
        )
        assertNotNull(runBlocking { RevengeCoilMediaFetcher(loader, request).fetch() })
        val cachedFile = assertNotNull(File(dir, "videoPreviews").listFiles()?.singleOrNull())
        val frame = assertNotNull(ImageIO.read(cachedFile))
        assertTrue(frame.width in 1..800)
        assertTrue(frame.height in 1..600)

        assertNotNull(runBlocking { RevengeCoilMediaFetcher(loader, request).fetch() })
        assertEquals(1, loader.thumbnailCalls)
        assertEquals(1, loader.downloadCalls)

        // Simulate the invalid MP4 cache left by the previous app release.
        cachedFile.writeBytes(video.readBytes())
        assertNotNull(runBlocking { RevengeCoilMediaFetcher(loader, request).fetch() })
        assertNotNull(ImageIO.read(cachedFile))
        assertEquals(2, loader.thumbnailCalls)
        assertEquals(2, loader.downloadCalls)
    }

    @Test
    fun oversizedVideoIsNotDownloadedForPreview() = withTempDirectory { dir ->
        val loader = FakeMediaLoader(dir)
        val request = MediaRequestData(
            MediaSource("mxc://example.test/large-video"),
            MediaRequestData.Kind.VideoThumbnail(null, "video/mp4", 81L * 1024L * 1024L),
        )
        assertNull(runBlocking { RevengeCoilMediaFetcher(loader, request).fetch() })
        assertEquals(1, loader.thumbnailCalls)
        assertEquals(0, loader.downloadCalls)
    }

    @Test
    fun failingServerThumbnailAlsoFallsBackToLocalFrame() = withTempDirectory { dir ->
        assumeTrue("ffmpeg is required for desktop video thumbnails", hasFfmpeg())
        val video = syntheticVideo(dir)
        val loader = FakeMediaLoader(dir).apply { videoFile = video }
        val request = MediaRequestData(
            MediaSource("mxc://example.test/failing-thumbnail"),
            MediaRequestData.Kind.VideoThumbnail(null, "video/mp4", video.length()),
        )
        assertNotNull(runBlocking { RevengeCoilMediaFetcher(loader, request).fetch() })
        assertNotNull(ImageIO.read(assertNotNull(File(dir, "videoPreviews").listFiles()?.singleOrNull())))
        assertEquals(1, loader.thumbnailCalls)
        assertEquals(1, loader.downloadCalls)
    }

    private fun syntheticVideo(dir: File): File {
        val video = File(dir, "clip.mp4")
        val process = ProcessBuilder(
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi",
            "-i", "color=c=red:s=96x64:r=5", "-t", "1",
            "-c:v", "mpeg4", "-y", video.absolutePath,
        ).redirectErrorStream(true).start()
        process.inputStream.use { it.readBytes() }
        assertTrue(process.waitFor(15, TimeUnit.SECONDS))
        assertEquals(0, process.exitValue())
        return video
    }

    private fun hasFfmpeg(): Boolean = runCatching {
        val process = ProcessBuilder("ffmpeg", "-version")
            .redirectOutput(ProcessBuilder.Redirect.DISCARD)
            .redirectError(ProcessBuilder.Redirect.DISCARD)
            .start()
        process.waitFor(5, TimeUnit.SECONDS) && process.exitValue() == 0
    }.getOrDefault(false)

    private fun jpeg(): ByteArray = ByteArrayOutputStream().use { stream ->
        ImageIO.write(BufferedImage(4, 4, BufferedImage.TYPE_INT_RGB), "jpg", stream)
        stream.toByteArray()
    }

    private inline fun withTempDirectory(block: (File) -> Unit) {
        val dir = Files.createTempDirectory("kite-video-fetcher-test-").toFile()
        try {
            block(dir)
        } finally {
            dir.deleteRecursively()
        }
    }

    private class FakeMediaLoader(override val baseCacheDirectory: File) : MatrixMediaLoader {
        var uploadedImage: ByteArray? = null
        var videoFile: File? = null
        var serverThumbnail: ByteArray? = null
        var contentCalls = 0
        var thumbnailCalls = 0
        var downloadCalls = 0

        override suspend fun loadMediaContent(source: MediaSource): Result<ByteArray> {
            contentCalls++
            return uploadedImage?.let { Result.success(it) }
                ?: Result.failure(IllegalStateException("No uploaded thumbnail"))
        }

        override suspend fun loadMediaThumbnail(
            source: MediaSource,
            width: Long,
            height: Long,
        ): Result<ByteArray> {
            thumbnailCalls++
            assertEquals(800L, width)
            assertEquals(600L, height)
            return serverThumbnail?.let { Result.success(it) }
                ?: Result.failure(IllegalStateException("Server cannot thumbnail video"))
        }

        override suspend fun downloadMediaFile(
            source: MediaSource,
            mimeType: String?,
            filename: String?,
            useCache: Boolean,
        ): Result<MediaFile> {
            downloadCalls++
            val file = videoFile ?: return Result.failure(IllegalStateException("No video"))
            return Result.success(object : MediaFile {
                override fun path() = file.absolutePath
                override fun persist(path: String) = false
                override fun close() = Unit
            })
        }
    }
}
