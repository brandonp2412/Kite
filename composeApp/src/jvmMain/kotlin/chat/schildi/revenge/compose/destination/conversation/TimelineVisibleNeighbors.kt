package chat.schildi.revenge.compose.destination.conversation

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import chat.schildi.revenge.Dimens

/** Timeline rows in newest-first order. Hidden rows do not separate visible bubbles. */
internal enum class TimelineRowKind { Event, Hidden, Boundary }

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
            TimelineRowKind.Boundary -> adjacent = -1
            TimelineRowKind.Hidden -> Unit
        }
    }
    adjacent = -1
    for (index in rows.indices) {
        newer[index] = adjacent
        when (rows[index]) {
            TimelineRowKind.Event -> adjacent = index
            TimelineRowKind.Boundary -> adjacent = -1
            TimelineRowKind.Hidden -> Unit
        }
    }
    return TimelineVisibleNeighbors(older, newer, olderAcrossDividers)
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
