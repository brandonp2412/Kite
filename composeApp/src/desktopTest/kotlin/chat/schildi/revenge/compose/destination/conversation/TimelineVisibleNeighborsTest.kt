package chat.schildi.revenge.compose.destination.conversation

import kotlin.test.Test
import kotlin.test.assertEquals
import androidx.compose.ui.unit.dp

class TimelineVisibleNeighborsTest {
    @Test
    fun messageGapDoesNotDependOnSenderGrouping() {
        // All adjacent rendered messages use the same 8 dp rhythm.
        assertEquals(8.dp, messageGapBeforeEvent(true, false))
        assertEquals(0.dp, messageGapBeforeEvent(false, false))
        assertEquals(0.dp, messageGapBeforeEvent(true, true))
    }

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
