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
    fun shortBackAndForthDoesNotAccumulateClockLabels() {
        val rows = List(8) { TimelineRowKind.Event }
        val timestamps = (7 downTo 0).map { 1_800_000_000_000L + it * 2 * 60 * 60_000L }
        val neighbors = calculateVisibleTimelineNeighbors(rows)
        val markers = calculateSparseTimeMarkers(rows, timestamps, neighbors.olderAcrossDividers, IntArray(rows.size) { 1 }, 10)
        assertEquals(0, markers.count { it })
    }

    @Test
    fun longSeparatedConversationKeepsOnlyScreenSpacedLabels() {
        val rows = List(32) { TimelineRowKind.Event }
        val start = java.time.LocalDateTime.of(2026, 11, 9, 18, 0)
            .atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
        var elapsedMinutes = 0L
        val timestamps = List(32) { index ->
            val timestamp = start - elapsedMinutes * 60_000L
            elapsedMinutes += if (index == 10 || index == 21) 61 else 1
            timestamp
        }
        val neighbors = calculateVisibleTimelineNeighbors(rows)
        val markers = calculateSparseTimeMarkers(rows, timestamps, neighbors.olderAcrossDividers, IntArray(rows.size) { 1 }, 10)
        val selected = markers.indices.filter { markers[it] }
        assertEquals(listOf(10, 21), selected)
        assertEquals(7, screenfulVisualUnitBudget(720f))
        assertEquals(5, screenfulVisualUnitBudget(360f))
    }

    @Test
    fun tallMessagesCanFillAViewportWithOnlyAFewEvents() {
        assertEquals(1, approximateMessageVisualUnits(20, false, 360f))
        assertEquals(3, approximateMessageVisualUnits(200, false, 360f))
        assertEquals(4, approximateMessageVisualUnits(10, true, 360f))

        val rows = List(6) { TimelineRowKind.Event }
        val start = java.time.LocalDateTime.of(2026, 11, 9, 16, 0)
            .atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
        val minutesAgo = listOf(0L, 1L, 2L, 40L, 70L, 71L)
        val timestamps = minutesAgo.map { start - it * 60_000L }
        val neighbors = calculateVisibleTimelineNeighbors(rows)
        val units = intArrayOf(1, 4, 4, 1, 1, 1)
        val markers = calculateSparseTimeMarkers(rows, timestamps, neighbors.olderAcrossDividers, units, 8)
        assertEquals(listOf(3), markers.indices.filter { markers[it] })

        // Sub-20-minute pauses are not significant, even after a full screen.
        val shorterPause = listOf(0L, 1L, 2L, 19L, 38L, 39L).map { start - it * 60_000L }
        val noMarkers = calculateSparseTimeMarkers(rows, shorterPause, neighbors.olderAcrossDividers, units, 8)
        assertEquals(0, noMarkers.count { it })
    }

    @Test
    fun twentyMinutePauseAppearsAfterMostOfAViewport() {
        val rows = List(9) { TimelineRowKind.Event }
        val start = java.time.LocalDateTime.of(2026, 11, 9, 18, 0)
            .atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
        val neighbors = calculateVisibleTimelineNeighbors(rows)
        val minutesAgo = listOf(0L, 1L, 2L, 3L, 4L, 5L, 6L, 7L, 27L)
        val markers = calculateSparseTimeMarkers(rows, minutesAgo.map { start - it * 60_000L },
            neighbors.olderAcrossDividers, IntArray(rows.size) { 1 }, 7)
        assertEquals(listOf(7), markers.indices.filter { markers[it] })

        val shortPause = minutesAgo.toMutableList().also { it[8] = 26L }
        val noMarkers = calculateSparseTimeMarkers(rows, shortPause.map { start - it * 60_000L },
            neighbors.olderAcrossDividers, IntArray(rows.size) { 1 }, 7)
        assertEquals(0, noMarkers.count { it })
    }

    @Test
    fun everyDayDividerRemainsVisibleInShortExchange() {
        val rows = listOf(
            TimelineRowKind.Event,
            TimelineRowKind.DayDivider,
            TimelineRowKind.Event,
            TimelineRowKind.DayDivider,
            TimelineRowKind.Event,
        )
        val timestamps = listOf(1_800_000_000_000L + 3 * 86_400_000L, null,
            1_800_000_000_000L + 2 * 86_400_000L, null, 1_800_000_000_000L)
        val neighbors = calculateVisibleTimelineNeighbors(rows)
        val markers = calculateSparseTimeMarkers(rows, timestamps, neighbors.olderAcrossDividers, IntArray(rows.size) { 1 }, 10)
        assertEquals(listOf(1, 3), markers.indices.filter { markers[it] })
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
