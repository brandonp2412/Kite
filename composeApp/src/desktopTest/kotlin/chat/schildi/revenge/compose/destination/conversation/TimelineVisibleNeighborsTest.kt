package chat.schildi.revenge.compose.destination.conversation

import kotlin.test.Test
import kotlin.test.assertEquals

class TimelineVisibleNeighborsTest {
    @Test
    fun invisibleServerEventsDoNotEraseSenderChangeGutters() {
        // A newer incoming bubble separated from an older outgoing bubble by
        // two invisible server events must still see the older visible sender.
        val neighbors = calculateVisibleTimelineNeighbors(listOf(
            TimelineRowKind.Event,
            TimelineRowKind.Hidden,
            TimelineRowKind.Hidden,
            TimelineRowKind.Event,
        ))
        assertEquals(3, neighbors.older[0])
        assertEquals(0, neighbors.newer[3])
    }

    @Test
    fun visibleDividersPreventCrossDayGrouping() {
        val neighbors = calculateVisibleTimelineNeighbors(listOf(
            TimelineRowKind.Event,
            TimelineRowKind.Hidden,
            TimelineRowKind.Boundary,
            TimelineRowKind.Hidden,
            TimelineRowKind.Event,
        ))
        assertEquals(-1, neighbors.older[0])
        assertEquals(-1, neighbors.newer[4])
    }

    @Test
    fun adjacentVisibleMessagesPreserveNormalGrouping() {
        val neighbors = calculateVisibleTimelineNeighbors(listOf(
            TimelineRowKind.Event,
            TimelineRowKind.Event,
        ))
        assertEquals(1, neighbors.older[0])
        assertEquals(0, neighbors.newer[1])
    }
}
