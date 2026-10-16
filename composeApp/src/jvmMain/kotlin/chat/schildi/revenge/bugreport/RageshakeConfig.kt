/*
 * Copyright (c) 2025 Element Creations Ltd.
 * Copyright 2024, 2025 New Vector Ltd.
 * Copyright 2024, 2026 SchildiChat
 *
 * SPDX-License-Identifier: AGPL-3.0-only
 * Please see LICENSE files in the repository root for full details.
 */

package chat.schildi.revenge.bugreport

object RageshakeConfig {
    /**
     * The maximum size of the upload request. Default value is just below CloudFlare's max request size.
     */
    const val MAX_LOG_UPLOAD_SIZE = 50 * 1024 * 1024L

    /**
     * The maximum size of a single log file.
     */
    const val MAX_LOG_CONTENT_SIZE = 100 * 1024 * 1024L

    /**
     * The maximum number of log lines a rageshake can contain.
     */
    const val MAX_LOG_LINES_SIZE = 1_000_000
}
