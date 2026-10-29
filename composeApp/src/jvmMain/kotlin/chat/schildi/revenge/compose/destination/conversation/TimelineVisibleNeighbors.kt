package chat.schildi.revenge.compose.destination.conversation

/** Timeline rows in newest-first order. Hidden rows do not separate visible bubbles. */
internal enum class TimelineRowKind { Event, Hidden, Boundary }

internal class TimelineVisibleNeighbors(val older: IntArray, val newer: IntArray)

/**
 * Find the nearest visible event on either side without crossing a visible timeline
 * divider. Compute once per timeline update instead of scanning on every row composition.
 */
internal fun calculateVisibleTimelineNeighbors(rows: List<TimelineRowKind>): TimelineVisibleNeighbors {
    val older = IntArray(rows.size) { -1 }
    val newer = IntArray(rows.size) { -1 }
    var adjacent = -1
    for (index in rows.indices.reversed()) {
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
    return TimelineVisibleNeighbors(older, newer)
}
