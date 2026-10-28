/*
 * Copyright (c) 2025 Element Creations Ltd.
 * Copyright 2023-2025 New Vector Ltd.
 *
 * SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
 * Please see LICENSE files in the repository root for full details.
 */

package io.element.android.libraries.matrix.ui.media

import chat.schildi.revenge.util.escapeForFilename
import coil3.decode.DataSource
import coil3.decode.ImageSource
import coil3.fetch.FetchResult
import coil3.fetch.Fetcher
import coil3.fetch.SourceFetchResult
import io.element.android.libraries.matrix.api.media.MatrixMediaLoader
import io.element.android.libraries.matrix.api.media.MediaSource
import io.element.android.libraries.matrix.api.media.toFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import okio.Buffer
import okio.FileSystem
import okio.Path.Companion.toOkioPath
import timber.log.Timber
import java.io.File
import java.nio.ByteBuffer
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest

/**
 * Revenge's alternative to upstream CoilMediaFetcher:
 * - Replaces MediaRequestData.Kind.Content with a file-based fetcher and bypasses SDK to read existing downloads.
 * - Disables Rust-SDK-based file cache for these requests
 */
internal class RevengeCoilMediaFetcher(
    private val mediaLoader: MatrixMediaLoader,
    private val mediaData: MediaRequestData,
) : Fetcher {

    private val cacheDir = File(mediaLoader.baseCacheDirectory, "mediaContent")

    override suspend fun fetch(): FetchResult? {
        val mediaSource = mediaData.source
        if (mediaSource == null) {
            Timber.e("MediaData source is null")
            return null
        }
        return when (val kind = mediaData.kind) {
            is MediaRequestData.Kind.Content -> fetchFile(mediaSource, buildFileForContentCache(mediaSource.safeUrl))
            is MediaRequestData.Kind.Thumbnail -> fetchThumbnail(mediaSource, kind)
            is MediaRequestData.Kind.VideoThumbnail -> fetchVideoThumbnail(mediaSource, kind)
            is MediaRequestData.Kind.File -> fetchFile(mediaSource, kind)
        }
    }

    private suspend fun buildFileForContentCache(url: String) = withContext(Dispatchers.IO) {
        MediaRequestData.Kind.File(
            fileName = url.removePrefix("mxc://").escapeForFilename(),
            mimeType = "application/octet-stream",
        )
    }

    private suspend fun fetchFile(mediaSource: MediaSource, kind: MediaRequestData.Kind.File): FetchResult? {
        val expectFile = File(mediaLoader.baseCacheDirectory, kind.fileName)
        if (expectFile.exists() && expectFile.isFile && expectFile.length() > 0) {
            return SourceFetchResult(
                source = ImageSource(
                    file = expectFile.toOkioPath(),
                    fileSystem = FileSystem.SYSTEM,
                    closeable = null,
                ),
                mimeType = null,
                dataSource = DataSource.DISK,
            )
        }
        return mediaLoader.downloadMediaFile(mediaSource, kind.mimeType, kind.fileName, useCache = false)
            .map { mediaFile ->
                expectFile.parentFile.mkdirs()
                mediaFile.use {
                    it.persist(expectFile.path)
                }
                SourceFetchResult(
                    source = ImageSource(
                        file = expectFile.toOkioPath(),
                        fileSystem = FileSystem.SYSTEM,
                        closeable = null,
                    ),
                    mimeType = null,
                    dataSource = DataSource.NETWORK,
                )
            }
            .onFailure {
                Timber.w("Failed to fetch file: $it")
            }
            .getOrNull()
    }

    /** Video events often have no uploaded thumbnail, especially bridged media. */
    private suspend fun fetchVideoThumbnail(
        mediaSource: MediaSource,
        kind: MediaRequestData.Kind.VideoThumbnail,
    ): FetchResult? {
        val key = videoPreviewCacheKey(mediaSource, kind)
        val cacheFile = File(mediaLoader.baseCacheDirectory, "videoPreviews/$key.img")
        return videoPreviewSemaphore.withPermit {
            if (cacheFile.isFile && cacheFile.length() > 0L) {
                if (cacheFile.hasImagePreviewHeader()) {
                    return@withPermit cacheFile.asCachedImageResult()
                }
                // Earlier builds could cache decrypted video bytes as if they were thumbnails.
                cacheFile.delete()
            }

            // An uploaded thumbnail is already an image; do not call /thumbnail on it.
            // Some homeservers return the original MP4 with a successful thumbnail response.
            val uploaded = kind.thumbnailSource?.let { thumbnailSource ->
                mediaLoader.loadMediaContent(thumbnailSource)
                    .onFailure { Timber.w("Failed to fetch uploaded video thumbnail: $it") }
                    .getOrNull()
            }?.takeIf { it.isImagePreview() }
            val server = if (uploaded == null) {
                mediaLoader.loadMediaThumbnail(mediaSource, kind.width, kind.height)
                    .onFailure { Timber.w("Failed to fetch server video thumbnail: $it") }
                    .getOrNull()
                    ?.takeIf { it.isImagePreview() }
            } else {
                null
            }
            val bytes = uploaded ?: server ?: extractVideoFrame(mediaSource, kind)
            if (bytes == null || !bytes.isImagePreview()) return@withPermit null
            val stored = runCatching {
                cacheFile.parentFile.mkdirs()
                val tempFile = File.createTempFile("video-preview-", ".tmp", cacheFile.parentFile)
                try {
                    tempFile.writeBytes(bytes)
                    Files.move(tempFile.toPath(), cacheFile.toPath(), StandardCopyOption.REPLACE_EXISTING)
                } finally {
                    tempFile.delete()
                }
                cacheFile
            }.onFailure { Timber.w("Unable to cache video thumbnail: $it") }.getOrNull()
            stored?.asCachedImageResult() ?: bytes.asSourceResult()
        }
    }

    private suspend fun extractVideoFrame(
        mediaSource: MediaSource,
        kind: MediaRequestData.Kind.VideoThumbnail,
    ): ByteArray? {
        if (kind.sizeBytes != null && kind.sizeBytes > MAX_VIDEO_FRAME_DOWNLOAD_BYTES) {
            Timber.d("Skipping large video preview download")
            return null
        }
        return mediaLoader.downloadMediaFile(
            source = mediaSource,
            mimeType = kind.mimeType ?: "video/mp4",
            filename = "video-preview-" + videoPreviewCacheKey(mediaSource, kind) + ".video",
            useCache = true,
        ).onFailure {
            Timber.w("Failed to download video for preview: $it")
        }.getOrNull()?.use { mediaFile ->
            val file = mediaFile.toFile()
            if (file.length() > MAX_VIDEO_FRAME_DOWNLOAD_BYTES) return@use null
            withContext(Dispatchers.IO) { VideoThumbnailPlatform.extractFrame(file) }
        }
    }

    private fun videoPreviewCacheKey(
        source: MediaSource,
        kind: MediaRequestData.Kind.VideoThumbnail,
    ): String {
        val input = source.safeUrl + "|" + kind.thumbnailSource?.safeUrl +
            "|" + kind.width + "x" + kind.height
        return MessageDigest.getInstance("SHA-256")
            .digest(input.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }
    }

    /** Reject media endpoints that return MP4/WebM instead of an actual image. */
    private fun ByteArray.isImagePreview(): Boolean {
        if (size >= 3 && this[0] == 0xff.toByte() &&
            this[1] == 0xd8.toByte() && this[2] == 0xff.toByte()
        ) return true // JPEG
        if (size >= 8 && this[0] == 0x89.toByte() &&
            copyOfRange(1, 4).contentEquals(byteArrayOf(0x50, 0x4e, 0x47))
        ) return true // PNG
        if (size >= 6 && copyOfRange(0, 3).decodeToString() == "GIF") return true
        if (size >= 2 && this[0] == 'B'.code.toByte() && this[1] == 'M'.code.toByte()) return true
        if (size >= 12) {
            val container = copyOfRange(0, 4).decodeToString()
            val codec = copyOfRange(8, 12).decodeToString()
            if (container == "RIFF" && codec == "WEBP") return true
            if (copyOfRange(4, 8).decodeToString() == "ftyp" &&
                codec in setOf("avif", "avis", "heic", "heix", "hevc", "mif1", "msf1")
            ) return true
        }
        return false
    }

    private fun File.hasImagePreviewHeader(): Boolean = runCatching {
        inputStream().use { input -> input.readNBytes(16).isImagePreview() }
    }.getOrDefault(false)

    private fun File.asCachedImageResult(): SourceFetchResult = SourceFetchResult(
        source = ImageSource(file = toOkioPath(), fileSystem = FileSystem.SYSTEM, closeable = null),
        mimeType = null,
        dataSource = DataSource.DISK,
    )

    private companion object {
        const val MAX_VIDEO_FRAME_DOWNLOAD_BYTES = 80L * 1024L * 1024L
        val videoPreviewSemaphore = Semaphore(2)
    }

    private suspend fun fetchThumbnail(mediaSource: MediaSource, kind: MediaRequestData.Kind.Thumbnail): FetchResult? {
        return mediaLoader.loadMediaThumbnail(
            source = mediaSource,
            width = kind.width,
            height = kind.height,
        ).map { byteArray ->
            byteArray.asSourceResult()
        }.onFailure {
            Timber.w("Failed to fetch thumbnail: $it")
        }.getOrNull()
    }

    private fun ByteArray.asSourceResult(): SourceFetchResult {
        val byteBuffer = ByteBuffer.wrap(this)
        val bufferedSource = try {
            Buffer().apply { write(byteBuffer) }
        } finally {
            byteBuffer.position(0)
        }
        return SourceFetchResult(
            source = ImageSource(
                source = bufferedSource,
                fileSystem = FileSystem.SYSTEM,
            ),
            mimeType = null,
            dataSource = DataSource.MEMORY
        )
    }
}
