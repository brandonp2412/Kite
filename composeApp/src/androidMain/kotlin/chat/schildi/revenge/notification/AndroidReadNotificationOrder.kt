package chat.schildi.revenge.notification

import chat.schildi.revenge.UiState
import co.touchlab.kermit.Logger
import io.element.android.libraries.matrix.api.MatrixClient
import io.element.android.libraries.matrix.api.core.EventId
import io.element.android.libraries.matrix.api.core.RoomId
import io.element.android.libraries.matrix.api.core.SessionId
import io.element.android.libraries.matrix.api.room.CreateTimelineParams
import io.element.android.libraries.matrix.api.timeline.MatrixTimelineItem
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Only invoked for an already posted notification whose exact receipt didn't match.
 * A focused SDK timeline supplies server-ordered events around each receipt.
 * We never dismiss when the read event cannot be ordered against the posted event.
 */
internal suspend fun maybeDismissNotificationByReadOrder(
    sessionId: SessionId,
    roomId: RoomId,
    readEventIds: List<EventId>,
    client: MatrixClient? = UiState.currentClientFor(sessionId),
): Boolean {
    if (readEventIds.isEmpty()) return false
    val postedId = AndroidNotifier.latestPostedEventId(sessionId.value, roomId.value) ?: return false
    if (client == null) return false
    return withTimeoutOrNull(4_000L) {
        client.getJoinedRoom(roomId)?.use { room ->
            // Context cached when the notification first arrived may end at that
            // message. Anchor on the read event to include its preceding messages.
            readEventIds.any { readId ->
                val timeline = room.createTimeline(
                    CreateTimelineParams.Focused(readId),
                    preferHideThreadedEvents = false,
                ).onFailure { Logger.withTag("AndroidReadNotificationOrder").w("Cannot load read context", it) }
                    .getOrNull() ?: return@any false
                try {
                    val context = timeline.timelineItems.first { items ->
                        items.any { it is MatrixTimelineItem.Event && it.eventId == readId }
                    }
                    val orderedIds = context.mapNotNull {
                        (it as? MatrixTimelineItem.Event)?.eventId?.value
                    }
                    readReceiptCoversNotification(postedId, listOf(readId.value), orderedIds) &&
                        AndroidNotifier.maybeAutoDismiss(sessionId.value, roomId.value, listOf(postedId))
                } finally {
                    timeline.close()
                }
            }
        } ?: false
    } ?: false
}
