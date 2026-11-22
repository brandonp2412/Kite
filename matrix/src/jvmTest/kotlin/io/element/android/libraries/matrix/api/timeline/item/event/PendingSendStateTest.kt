/*
 * Copyright (c) 2026 Kite contributors.
 * SPDX-License-Identifier: AGPL-3.0-only.
 */

package io.element.android.libraries.matrix.api.timeline.item.event

import io.element.android.libraries.matrix.api.timeline.item.SendTarget
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class PendingSendStateTest {
    private val failed = LocalEventSendState.Failed.Unknown("send queue blocked")
    private val sending = LocalEventSendState.Sending.Event

    @Test
    fun failedEditIsVisibleEvenAfterOriginalMessageWasSent() {
        assertEquals(SendTarget.Edit to failed, pendingSendForStates(null, failed, null))
    }

    @Test
    fun failedRedactionCanBeRetriedEvenWhenAnotherSendIsInProgress() {
        assertEquals(SendTarget.Redaction to failed, pendingSendForStates(sending, null, failed))
    }

    @Test
    fun sendingEditRemainsVisibleAndSentOrMissingStatesDoNot() {
        assertEquals(SendTarget.Edit to sending, pendingSendForStates(null, sending, null))
        assertNull(pendingSendForStates(null, null, null))
    }
}
