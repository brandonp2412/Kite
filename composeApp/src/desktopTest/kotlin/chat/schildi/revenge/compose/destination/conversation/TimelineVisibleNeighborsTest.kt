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
    fun selectedMessagesShareTheirInterveningGapOnly() {
        assertEquals(true, shouldHighlightMessageGap(true, true, true, false))
        assertEquals(false, shouldHighlightMessageGap(true, false, true, false))
        assertEquals(false, shouldHighlightMessageGap(false, true, true, false))
        assertEquals(false, shouldHighlightMessageGap(true, true, false, false))
        assertEquals(false, shouldHighlightMessageGap(true, true, true, true))
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
    fun fifteenMinutePauseStartsNewVisibleTimeGroup() {
        val base = 1_800_000_000_000L
        assertEquals(false, shouldShowMessageTimeSeparator(base, null))
        assertEquals(false, shouldShowMessageTimeSeparator(base, base))
        assertEquals(false, shouldShowMessageTimeSeparator(base + 14 * 60_000L + 59_999L, base))
        assertEquals(true, shouldShowMessageTimeSeparator(base + 15 * 60_000L, base))
        assertEquals(true, shouldShowMessageTimeSeparator(base + 26 * 60_000L, base))
        assertEquals(false, shouldShowMessageTimeSeparator(base - 60_000L, base))
    }

    @Test
    fun timeGroupsFollowVisibleMessagesAcrossDateAndUnreadDividers() {
        val neighbors = calculateVisibleTimelineNeighbors(listOf(
            TimelineRowKind.Event,
            TimelineRowKind.Hidden,
            TimelineRowKind.Boundary,
            TimelineRowKind.Event,
            TimelineRowKind.Boundary,
            TimelineRowKind.Event,
        ))
        assertEquals(3, neighbors.olderAcrossDividers[0])
        assertEquals(5, neighbors.olderAcrossDividers[3])
        assertEquals(-1, neighbors.olderAcrossDividers[5])
        assertEquals(-1, neighbors.older[0]) // Bubble grouping still stops at dividers.
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
