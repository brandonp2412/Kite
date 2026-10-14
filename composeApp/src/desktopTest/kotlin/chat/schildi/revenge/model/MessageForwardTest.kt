package chat.schildi.revenge.model

import io.element.android.libraries.matrix.api.core.EventId
import io.element.android.libraries.matrix.api.core.RoomId
import io.element.android.libraries.matrix.api.core.UserId
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toImmutableList
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MessageForwardTest {
    private val sessionId = UserId("@kite:test")
    private val sourceRoomId = RoomId("!source:test")
    private val firstEventId = EventId("$" + "first:test")
    private val secondEventId = EventId("$" + "second:test")

    @AfterTest
    fun cleanup() {
        MessageForward.clear()
    }

    @Test
    fun staleOperationCannotConsumeReplacement() {
        val first = forward(1, listOf(firstEventId))
        val replacement = forward(2, listOf(firstEventId))
        MessageForward.set(first)
        MessageForward.set(replacement)

        assertFalse(MessageForward.markForwarded(first, firstEventId))
        assertEquals(replacement, MessageForward.pending.value)
        assertTrue(MessageForward.markForwarded(replacement, firstEventId))
        assertNull(MessageForward.pending.value)
    }

    @Test
    fun partialForwardKeepsOperationIdentityAndRemainingEvents() {
        val forward = forward(3, listOf(firstEventId, secondEventId))
        MessageForward.set(forward)

        assertTrue(MessageForward.markForwarded(forward, firstEventId))
        val remaining = MessageForward.pending.value
        assertEquals(forward.operationId, remaining?.operationId)
        assertEquals(persistentListOf(secondEventId), remaining?.eventIds)
        assertTrue(MessageForward.isCurrent(forward))
        assertTrue(MessageForward.clear(forward))
        assertNull(MessageForward.pending.value)
    }

    @Test
    fun staleClearCannotCancelNewForward() {
        val first = forward(4, listOf(firstEventId))
        val replacement = forward(5, listOf(secondEventId))
        MessageForward.set(first)
        MessageForward.set(replacement)

        assertFalse(MessageForward.clear(first))
        assertEquals(replacement, MessageForward.pending.value)
    }

    private fun forward(operationId: Long, eventIds: List<EventId>) = PendingMessageForward(
        operationId = operationId,
        sessionId = sessionId,
        sourceRoomId = sourceRoomId,
        eventIds = eventIds.toImmutableList(),
    )
}
