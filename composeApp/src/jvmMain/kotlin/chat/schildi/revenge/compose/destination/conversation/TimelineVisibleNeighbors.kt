package chat.schildi.revenge.compose.destination.conversation

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import chat.schildi.revenge.Dimens

/** Timeline rows in newest-first order. Hidden rows do not separate visible bubbles. */
internal enum class TimelineRowKind { Event, Hidden, Boundary, DayDivider }

internal class TimelineVisibleNeighbors(
    val older: IntArray,
    val newer: IntArray,
    val olderAcrossDividers: IntArray,
)

/**
 * Find the nearest visible event on either side without crossing a visible timeline
 * divider. Compute once per timeline update instead of scanning on every row composition.
 */
internal fun calculateVisibleTimelineNeighbors(rows: List<TimelineRowKind>): TimelineVisibleNeighbors {
    val older = IntArray(rows.size) { -1 }
    val newer = IntArray(rows.size) { -1 }
    val olderAcrossDividers = IntArray(rows.size) { -1 }
    var previousEvent = -1
    var adjacent = -1
    for (index in rows.indices.reversed()) {
        olderAcrossDividers[index] = previousEvent
        if (rows[index] == TimelineRowKind.Event) previousEvent = index
        older[index] = adjacent
        when (rows[index]) {
            TimelineRowKind.Event -> adjacent = index
            TimelineRowKind.Boundary, TimelineRowKind.DayDivider -> adjacent = -1
            TimelineRowKind.Hidden -> Unit
        }
    }
    adjacent = -1
    for (index in rows.indices) {
        newer[index] = adjacent
        when (rows[index]) {
            TimelineRowKind.Event -> adjacent = index
            TimelineRowKind.Boundary, TimelineRowKind.DayDivider -> adjacent = -1
            TimelineRowKind.Hidden -> Unit
        }
    }
    return TimelineVisibleNeighbors(older, newer, olderAcrossDividers)
}

/**
 * Select time labels once per timeline update. A 20-minute pause is only a candidate;
 * nearby back-and-forth messages do not produce multiple labels on one screen.
 * Day dividers always remain visible; only clock labels use the screen spacing budget.
 */
internal fun calculateSparseTimeMarkers(
    kinds: List<TimelineRowKind>,
    timestamps: List<Long?>,
    olderMessageIndices: IntArray,
    visualUnits: IntArray,
    screenfulUnits: Int,
): BooleanArray {
    require(kinds.size == timestamps.size && kinds.size == olderMessageIndices.size &&
        kinds.size == visualUnits.size)
    val markers = BooleanArray(kinds.size)
    var messagesSinceMarker = 0
    for (index in kinds.indices) { // Newest first, so current context wins.
        when (kinds[index]) {
            TimelineRowKind.DayDivider -> {
                // Each calendar-day transition must remain identifiable, even if
                // only one or two messages were exchanged on either day.
                markers[index] = true
                messagesSinceMarker = 0
            }
            TimelineRowKind.Event -> {
                val timestamp = timestamps[index]
                val olderIndex = olderMessageIndices[index]
                val olderTimestamp = if (olderIndex >= 0) timestamps[olderIndex] else null
                if (timestamp != null && olderTimestamp != null &&
                    timestamp >= olderTimestamp &&
                    timestamp - olderTimestamp >= 20L * 60L * 1000L &&
                    messagesSinceMarker >= screenfulUnits &&
                    // The day divider already communicates a date change.
                    chat.schildi.revenge.DateTimeFormat.timestampToDateTime(timestamp).toLocalDate() ==
                    chat.schildi.revenge.DateTimeFormat.timestampToDateTime(olderTimestamp).toLocalDate()
                ) {
                    markers[index] = true
                    messagesSinceMarker = 0
                }
                messagesSinceMarker += visualUnits[index].coerceAtLeast(1)
            }
            TimelineRowKind.Hidden, TimelineRowKind.Boundary -> Unit
        }
    }
    return markers
}

/**
 * Approximate the conversation viewport (excluding navigation/composer), not the
 * entire screen. Values stay stable while scrolling or opening the keyboard.
 */
internal fun screenfulVisualUnitBudget(windowHeightDp: Float): Int =
    kotlin.math.ceil((windowHeightDp - 160f).coerceAtLeast(320f) / 80f).toInt().coerceAtLeast(5)

/** Weight long text and tall media more than a one-line bubble. Computed once per timeline update. */
internal fun approximateMessageVisualUnits(bodyLength: Int, tallMedia: Boolean, windowWidthDp: Float): Int {
    val charactersPerLine = ((windowWidthDp.coerceAtMost(620f) * 0.72f) / 8f).toInt().coerceAtLeast(20)
    val textLines = (bodyLength.coerceAtLeast(1) + charactersPerLine - 1) / charactersPerLine
    val estimatedHeightDp = 24f + textLines * 24f + if (tallMedia) 200f else 0f
    return kotlin.math.ceil(estimatedHeightDp / 64f).toInt().coerceIn(1, 10)
}

// Unread markers and day boundaries own their own vertical separation.
/** Show an unobtrusive clock above a message after a 15-minute pause. */
internal fun shouldShowMessageTimeSeparator(timestamp: Long, olderTimestamp: Long?): Boolean =
    olderTimestamp != null && timestamp >= olderTimestamp &&
        timestamp - olderTimestamp >= 15L * 60L * 1000L

/** Connect selected backgrounds only across a real message gap, never across an unread divider. */
internal fun shouldHighlightMessageGap(
    isSelected: Boolean,
    olderMessageSelected: Boolean,
    hasOlderVisibleMessage: Boolean,
    hasUnreadSeparator: Boolean,
): Boolean = isSelected && olderMessageSelected && hasOlderVisibleMessage && !hasUnreadSeparator

internal fun messageGapBeforeEvent(
    hasOlderVisibleMessage: Boolean,
    hasUnreadSeparator: Boolean,
): Dp = if (hasOlderVisibleMessage && !hasUnreadSeparator) {
    Dimens.Conversation.messageRowSpacing
} else {
    0.dp
}
