package chat.schildi.revenge.notification

import chat.schildi.revenge.UiState
import co.touchlab.kermit.Logger
import io.element.android.libraries.matrix.api.core.EventId
import io.element.android.libraries.matrix.api.core.RoomId
import io.element.android.libraries.matrix.api.core.SessionId
import io.element.android.libraries.matrix.api.room.CreateTimelineParams
import io.element.android.libraries.matrix.api.timeline.MatrixTimelineItem
import io.element.android.libraries.matrix.api.timeline.Timeline
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Only invoked for an already posted notification whose exact receipt didn't match.
 * A focused SDK timeline supplies server-ordered events around the notification.
 * We never dismiss when the read event cannot be ordered against the posted event.
 */
internal suspend fun maybeDismissNotificationByReadOrder(
    sessionId: SessionId,
    roomId: RoomId,
    readEventIds: List<EventId>,
): Boolean {
    if (readEventIds.isEmpty()) return false
    val postedId = AndroidNotifier.latestPostedEventId(sessionId.value, roomId.value) ?: return false
    val client = UiState.currentClientFor(sessionId) ?: return false
    return withTimeoutOrNull(4_000L) {
        client.getJoinedRoom(roomId)?.use { room ->
            val timeline = room.createTimeline(
                CreateTimelineParams.Focused(EventId(postedId)),
                preferHideThreadedEvents = false,
            ).onFailure { Logger.withTag("AndroidReadNotificationOrder").w("Cannot load read context", it) }
                .getOrNull() ?: return@use false
            try {
                val context = timeline.timelineItems.first { items ->
                    items.any { it is MatrixTimelineItem.Event && it.eventId?.value == postedId }
                }
                val orderedIds = context.mapNotNull {
                    (it as? MatrixTimelineItem.Event)?.eventId?.value
                }
                if (readReceiptCoversNotification(postedId, readEventIds.map(EventId::value), orderedIds)) {
                    AndroidNotifier.dismiss(sessionId.value, roomId.value)
                } else {
                    // A newer unread event remains newer even if the room contains
                    // some older read events. Never approximate using timestamps.
                    false
                }
            } finally {
                timeline.close()
            }
        } ?: false
    } ?: false
}
