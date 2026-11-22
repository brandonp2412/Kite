/*
 * Copyright (c) 2026 Element Creations Ltd.
 *
 * SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
 * Please see LICENSE files in the repository root for full details.
 */

package io.element.android.libraries.matrix.api.timeline.item

import androidx.compose.runtime.Immutable

/** Identifies which pending send operation belongs to a timeline item. */
@Immutable
sealed interface SendTarget {
    data object Event : SendTarget
    data object Edit : SendTarget
    data object Redaction : SendTarget
    data class Reaction(val key: String) : SendTarget
}
