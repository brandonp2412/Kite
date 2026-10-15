package chat.schildi.revenge.compose.destination.conversation

import kotlin.test.Test
import kotlin.test.assertEquals

class UnreadTimelinePositionTest {
    @Test
    fun opensAtFirstUnreadMessageRatherThanTheReadEventOrDivider() {
        val types = listOf("message", "read", "divider", "message", "message")
        assertEquals(3, firstUnreadTimelineIndex(1, types.size) { types[it] == "message" })
    }

    @Test
    fun openingUnreadRoomTargetsNewestMessageEvenWithTrailingVirtualRows() {
        val types = listOf("read", "message", "message", "typing")
        assertEquals(2, latestTimelineIndex(types.size) { types[it] == "message" })
        assertEquals(0, latestTimelineIndex(3) { false })
    }

    @Test
    fun fallsBackToReadMarkerWhenThereIsNothingUnread() {
        assertEquals(3, firstUnreadTimelineIndex(3, 4) { true })
        assertEquals(1, firstUnreadTimelineIndex(1, 3) { false })
    }

    @Test
    fun followsLatestOnlyWhenAtActualBottom() {
        kotlin.test.assertTrue(isLatestPosition(0, 0))
        kotlin.test.assertFalse(isLatestPosition(0, 14))
        kotlin.test.assertFalse(isLatestPosition(1, 0))
    }

    @Test
    fun alignsShortAndTallUnreadRowsWithoutAssumingWindowHeight() {
        assertEquals(-434, unreadTopScrollOffset(700, 250, 16))
        assertEquals(316, unreadTopScrollOffset(700, 1000, 16))
    }
}
