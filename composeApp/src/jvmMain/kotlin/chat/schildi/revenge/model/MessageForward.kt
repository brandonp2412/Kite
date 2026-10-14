package chat.schildi.revenge.model

import io.element.android.libraries.matrix.api.core.EventId
import io.element.android.libraries.matrix.api.core.RoomId
import io.element.android.libraries.matrix.api.core.SessionId
import io.element.android.libraries.matrix.api.timeline.item.event.EventTimelineItem
import java.util.concurrent.atomic.AtomicLong
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

data class PendingMessageForward(
    val operationId: Long,
    val sessionId: SessionId,
    val sourceRoomId: RoomId,
    val eventIds: ImmutableList<EventId>,
)

object MessageForward {
    private val nextOperationId = AtomicLong(0)
    private val _pending = MutableStateFlow<PendingMessageForward?>(null)
    val pending = _pending.asStateFlow()

    /**
     * Capture only stable identifiers for a forward operation.
     *
     * Message content is deliberately not re-serialized here. The Matrix Rust SDK already exposes
     * Timeline.forwardEvent(), which understands decrypted/media content and creates proper forwarded
     * events without leaking source-room reply/thread relations into the destination room.
     */
    fun prepare(
        sessionId: SessionId,
        sourceRoomId: RoomId,
        events: List<EventTimelineItem>,
    ): PendingMessageForward? {
        if (events.isEmpty()) return null
        val eventIds = events.mapNotNull { it.eventId }
        if (eventIds.size != events.size) return null
        return PendingMessageForward(
            operationId = nextOperationId.incrementAndGet(),
            sessionId = sessionId,
            sourceRoomId = sourceRoomId,
            eventIds = eventIds.toImmutableList(),
        )
    }

    fun set(forward: PendingMessageForward) {
        _pending.value = forward
    }

    fun isCurrent(expected: PendingMessageForward): Boolean =
        _pending.value?.operationId == expected.operationId

    /**
     * Remove one successfully forwarded event from the pending batch.
     *
     * The operation id prevents a stale async forward from consuming a newer forward request that
     * happens to contain the same source event.
     */
    fun markForwarded(expected: PendingMessageForward, eventId: EventId): Boolean {
        while (true) {
            val current = _pending.value ?: return false
            if (current.operationId != expected.operationId || eventId !in current.eventIds) {
                return false
            }
            val remaining = current.eventIds.filterNot { it == eventId }.toImmutableList()
            val next = if (remaining.isEmpty()) null else current.copy(eventIds = remaining)
            if (_pending.compareAndSet(current, next)) return true
        }
    }

    fun clear(expected: PendingMessageForward? = null): Boolean {
        while (true) {
            val current = _pending.value ?: return false
            if (expected != null && current.operationId != expected.operationId) return false
            if (_pending.compareAndSet(current, null)) return true
        }
    }
}
