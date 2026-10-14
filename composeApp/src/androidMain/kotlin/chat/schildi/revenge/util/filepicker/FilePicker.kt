package chat.schildi.revenge.util.filepicker

import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import chat.schildi.revenge.RevengeApplication
import chat.schildi.revenge.WindowId
import chat.schildi.revenge.actions.fileProviderAuthority
import chat.schildi.revenge.androidWindowManager
import chat.schildi.revenge.util.StartupCacheCleaner
import chat.schildi.revenge.util.toSafeFilename
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.coroutines.resume
import kotlin.uuid.Uuid

actual val availableAttachmentPickerKinds: Set<AttachmentPickerKind> = AttachmentPickerKind.entries.toSet()

actual object FilePicker {
    actual suspend fun requestFilePicker(
        title: String,
        windowId: WindowId,
        kind: AttachmentPickerKind,
    ): Result<FilePickerResult?> {
        return try {
            when (kind) {
                AttachmentPickerKind.FILE -> requestDocument(windowId, arrayOf("*/*"))
                AttachmentPickerKind.GALLERY -> requestDocument(windowId, arrayOf("image/*", "video/*"))
                AttachmentPickerKind.CAMERA -> requestCamera(windowId)
            }
        } catch (exception: CancellationException) {
            throw exception
        } catch (throwable: Throwable) {
            Result.failure(throwable)
        }
    }

    private suspend fun requestDocument(
        windowId: WindowId,
        mimeTypes: Array<String>,
    ): Result<FilePickerResult?> {
        val uri = withContext(Dispatchers.Main.immediate) {
            val activity = androidWindowManager.getActivity(windowId)
                ?: error("The window is not attached to an Android activity")
            activity.filePickerLauncher.requestDocument(mimeTypes)
        }
        return if (uri == null) {
            Result.success(null)
        } else {
            copyUriToCache(uri)
        }
    }

    private suspend fun requestCamera(windowId: WindowId): Result<FilePickerResult?> {
        val importDir = ComposerAttachmentCache.createImportDir()
        val destination = File(importDir, "camera-" + System.currentTimeMillis() + ".jpg")
        return try {
            check(destination.createNewFile()) { "Failed to create camera attachment file" }
            val captured = withContext(Dispatchers.Main.immediate) {
                val activity = androidWindowManager.getActivity(windowId)
                    ?: error("The window is not attached to an Android activity")
                val uri = FileProvider.getUriForFile(
                    activity,
                    activity.fileProviderAuthority,
                    destination,
                )
                activity.filePickerLauncher.requestCamera(uri)
            }
            if (!captured || destination.length() == 0L) {
                importDir.deleteRecursively()
                Result.success(null)
            } else {
                Result.success(FilePickerResult(destination, "image/jpeg", true))
            }
        } catch (exception: CancellationException) {
            importDir.deleteRecursively()
            throw exception
        } catch (throwable: Throwable) {
            importDir.deleteRecursively()
            Result.failure(throwable)
        }
    }

    internal suspend fun copyUriToCache(uri: Uri): Result<FilePickerResult> = withContext(Dispatchers.IO) {
        val application = RevengeApplication.instance
        val resolver = application.contentResolver
        val displayName = resolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            val nameColumn = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (nameColumn >= 0 && cursor.moveToFirst()) cursor.getString(nameColumn) else null
        }
        val mimeType = resolver.getType(uri)
        val filename = safeFilename(displayName, mimeType)
        val importDir = ComposerAttachmentCache.createImportDir()
        val destination = File(importDir, filename)

        try {
            val input = resolver.openInputStream(uri)
                ?: error("The selected document could not be opened")
            input.use { source ->
                destination.outputStream().use(source::copyTo)
            }
            Result.success(
                FilePickerResult(
                    file = destination,
                    mimeType = mimeType,
                    isAppOwned = true,
                )
            )
        } catch (throwable: Throwable) {
            importDir.deleteRecursively()
            Result.failure(throwable)
        }
    }

    private fun safeFilename(displayName: String?, mimeType: String?): String {
        val candidate = displayName
            ?.substringAfterLast('/')
            ?.substringAfterLast('\\')
            ?.takeIf(String::isNotEmpty)
            ?.toSafeFilename(fallback = "attachment")
            ?: "attachment"
        val existingExtension = candidate.substringAfterLast('.', missingDelimiterValue = "")
            .takeIf(String::isNotEmpty)
        val inferredExtension = mimeType
            ?.let(MimeTypeMap.getSingleton()::getExtensionFromMimeType)
            ?.takeIf(String::isNotEmpty)
        val extension = existingExtension ?: inferredExtension
        val suffix = extension?.let { ".$it" }.orEmpty()
        val stem = if (existingExtension == null) candidate else candidate.dropLast(existingExtension.length + 1)
        return (stem + suffix).toSafeFilename(
            fallback = "attachment$suffix",
        )
    }
}

internal object ComposerAttachmentCache {
    private val baseDir: File
        get() = File(RevengeApplication.instance.cacheDir, "composerAttachments")
    private val startupCleaner = StartupCacheCleaner {
        baseDir.deleteRecursively()
    }

    suspend fun createImportDir(): File {
        startupCleaner.awaitClear()
        return File(baseDir, Uuid.random().toString()).also {
            check(it.mkdirs()) { "Failed to create composer attachment cache directory" }
        }
    }

    fun clearAsync(scope: CoroutineScope) {
        startupCleaner.clearAsync(scope)
    }
}

internal class AndroidFilePickerLauncher(activity: ComponentActivity) {
    private var pendingDocumentRequest: CancellableContinuation<Uri?>? = null
    private var pendingCameraRequest: CancellableContinuation<Boolean>? = null

    private val documentLauncher = activity.registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        takePendingDocumentRequest()?.resume(uri)
    }
    private val cameraLauncher = activity.registerForActivityResult(ActivityResultContracts.TakePicture()) { captured ->
        takePendingCameraRequest()?.resume(captured)
    }

    suspend fun requestDocument(mimeTypes: Array<String>): Uri? = suspendCancellableCoroutine { continuation ->
        synchronized(this) {
            check(pendingDocumentRequest == null && pendingCameraRequest == null) {
                "An attachment picker is already open for this window"
            }
            pendingDocumentRequest = continuation
        }
        continuation.invokeOnCancellation {
            synchronized(this) {
                if (pendingDocumentRequest === continuation) pendingDocumentRequest = null
            }
        }
        try {
            documentLauncher.launch(mimeTypes)
        } catch (throwable: Throwable) {
            synchronized(this) {
                if (pendingDocumentRequest === continuation) pendingDocumentRequest = null
            }
            continuation.resumeWith(Result.failure(throwable))
        }
    }

    suspend fun requestCamera(uri: Uri): Boolean = suspendCancellableCoroutine { continuation ->
        synchronized(this) {
            check(pendingDocumentRequest == null && pendingCameraRequest == null) {
                "An attachment picker is already open for this window"
            }
            pendingCameraRequest = continuation
        }
        continuation.invokeOnCancellation {
            synchronized(this) {
                if (pendingCameraRequest === continuation) pendingCameraRequest = null
            }
        }
        try {
            cameraLauncher.launch(uri)
        } catch (throwable: Throwable) {
            synchronized(this) {
                if (pendingCameraRequest === continuation) pendingCameraRequest = null
            }
            continuation.resumeWith(Result.failure(throwable))
        }
    }

    fun close() {
        takePendingDocumentRequest()?.cancel(CancellationException("The attachment picker activity was destroyed"))
        takePendingCameraRequest()?.cancel(CancellationException("The attachment picker activity was destroyed"))
    }

    private fun takePendingDocumentRequest(): CancellableContinuation<Uri?>? = synchronized(this) {
        pendingDocumentRequest.also { pendingDocumentRequest = null }
    }

    private fun takePendingCameraRequest(): CancellableContinuation<Boolean>? = synchronized(this) {
        pendingCameraRequest.also { pendingCameraRequest = null }
    }
}
