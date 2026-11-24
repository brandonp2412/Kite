package chat.schildi.revenge.notification

/**
 * Compare room events by their Matrix timeline order, never by timestamp or
 * opaque event ID. Fail closed when either event is outside the loaded context.
 */
internal fun readReceiptCoversNotification(
    postedEventId: String,
    readEventIds: List<String>,
    chronologicalEventIds: List<String>,
): Boolean {
    val postedIndex = chronologicalEventIds.indexOf(postedEventId)
    if (postedIndex < 0) return false
    return readEventIds.any { readEventId ->
        val readIndex = chronologicalEventIds.indexOf(readEventId)
        readIndex >= postedIndex
    }
}
