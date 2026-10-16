/*
 * Copyright (c) 2025 Element Creations Ltd.
 * Copyright 2023-2025 New Vector Ltd.
 * Copyright 2026 SchildiChat
 *
 * SPDX-License-Identifier: AGPL-3.0-only
 * Please see LICENSE files in the repository root for full details.
 */

package chat.schildi.revenge.bugreport

import chat.schildi.lib.preferences.ScPreferencesStore
import chat.schildi.lib.preferences.ScPrefs
import chat.schildi.lib.preferences.collectScPrefs
import chat.schildi.revenge.BuildInfo
import chat.schildi.revenge.UiState
import chat.schildi.revenge.actions.ActionResult
import chat.schildi.revenge.config.ScAppDirs
import chat.schildi.revenge.config.keybindings.ActionArgument
import chat.schildi.revenge.glue.RevengeOkHttpClient
import chat.schildi.revenge.glue.RevengeSessionStore
import chat.schildi.revenge.glue.platformApplicationId
import chat.schildi.revenge.glue.platformOsDebugName
import chat.schildi.revenge.glue.platformVersionCode
import chat.schildi.revenge.glue.platformVersionName
import chat.schildi.revenge.preferences.RevengePrefs
import io.element.android.libraries.androidutils.file.safeDelete
import io.element.android.libraries.core.data.tryOrNull
import io.element.android.libraries.core.mimetype.MimeTypes
import io.element.android.libraries.sessionstorage.api.SessionStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.Response
import timber.log.Timber
import java.io.File
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.text.SimpleDateFormat
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Date
import java.util.Locale

/**
 * Whether calling [getPlatformLogContent] makes sense on this device.
 */
expect val canReadPlatformLog: Boolean
/**
 * Retrieves the logs from the OS, e.g. logcat on Android.
 *
 * @param streamWriter the stream writer
 */
expect fun getPlatformLogContent(streamWriter: OutputStreamWriter)

val RevengeBugReporter = BugReporter()

/**
 * BugReporter creates and sends the bug reports.
 */
class BugReporter(
    private val okHttpClient: () -> OkHttpClient = { RevengeOkHttpClient  },
    private val sessionStore: SessionStore = RevengeSessionStore,
    private val scPreferencesStore: ScPreferencesStore = RevengePrefs,
) {
    companion object {
        // filenames
        private const val PLATFORM_LOG = "platform.log"
    }

    private var currentTracingLogLevel: String? = null

    private val currentLogDirectory = File(ScAppDirs.getUserLogDir())

    @Suppress("UNUSED_PARAMETER")
    suspend fun sendBugReport(
        problemDescription: String,
        reportContext: List<Pair<ActionArgument, String>> = emptyList(),
        withDevicesLogs: Boolean = true,
        canContact: Boolean = false,
        ghIssueNumber: Int? = null,
        onProgress: (percentage: Int) -> Unit = {},
    ): ActionResult = ActionResult.Failure(
        "Kite does not upload diagnostic logs. Report an issue at https://github.com/brandonp2412/Kite/issues/new",
    )

    /**
     * @return the files on the log directory.
     */
    private fun getLogFiles(): List<File> {
        return tryOrNull(
            onException = { Timber.e(it, "## getLogFiles() failed") }
        ) {
            val logDirectory = currentLogDirectory
            logDirectory.listFiles()
                ?.filter {
                    it.isFile &&
                        !it.name.endsWith(PLATFORM_LOG)
                }
        }.orEmpty()
    }

    // ==============================================================================================================
    // Logcat management
    // ==============================================================================================================

    /**
     * Save the platform log, e.g. logcat.
     *
     * @return the file if the operation succeeds
     */
    fun savePlatformLog(): File? {
        val file = File(currentLogDirectory, PLATFORM_LOG)
        if (file.exists()) {
            file.safeDelete()
        }
        return try {
            file.writer().use {
                getPlatformLogContent(it)
            }
            file
        } catch (e: Exception) {
            Timber.e(e, "## saveLogCat() : fail to write logcat")
            null
        }
    }

    private fun countLogLines(file: File): Int {
        return file.reader().useLines { it.count() }
    }
}

fun String?.ensureNonEmpty(fallback: String = "∅"): String {
    return if (isNullOrEmpty()) {
        // GitHub markdown format doesn't like empty code blocks
        fallback
    } else {
        this
    }
}
