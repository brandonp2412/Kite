/*
 * Copyright (c) 2026 Element Creations Ltd.
 *
 * SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
 * Please see LICENSE files in the repository root for full details.
 */

package io.element.android.libraries.matrix.impl.timeline

import io.element.android.libraries.matrix.api.timeline.item.SendTarget

internal fun SendTarget.map() = when (this) {
    SendTarget.Event -> org.matrix.rustcomponents.sdk.SendTarget.Event
    SendTarget.Edit -> org.matrix.rustcomponents.sdk.SendTarget.Edit
    SendTarget.Redaction -> org.matrix.rustcomponents.sdk.SendTarget.Redaction
    is SendTarget.Reaction -> org.matrix.rustcomponents.sdk.SendTarget.Reaction(key)
}
