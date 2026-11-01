package chat.schildi.revenge.notification

import chat.schildi.revenge.ScCoroutines
import chat.schildi.revenge.UiState
import chat.schildi.revenge.model.RevengeRoomListDataSource
import chat.schildi.revenge.model.ScopedRawRoomId
import co.touchlab.kermit.Logger
import io.element.android.libraries.matrix.api.core.EventId
import io.element.android.libraries.matrix.api.timeline.ReceiptType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlin.concurrent.atomics.AtomicBoolean
import kotlin.concurrent.atomics.ExperimentalAtomicApi

/** Reconcile Android notifications with read state delivered by the existing Matrix room sync. */
internal object AndroidReadNotificationSync {
    private val log = Logger.withTag("AndroidReadNotificationSync")
    private val scope = ScCoroutines.scope(Dispatchers.IO, "AndroidReadNotificationSync")
    @OptIn(ExperimentalAtomicApi::class)
    private val launched = AtomicBoolean(false)

    @OptIn(ExperimentalAtomicApi::class)
    fun launch() {
        if (launched.exchange(true)) return

        var previousStates = emptyMap<ScopedRawRoomId, NotificationReadState>()
        RevengeRoomListDataSource.allRooms.onEach { rooms ->
            // The room list is already synchronized by Kite. Do not poll or subscribe to a
            // second timeline for every conversation, and never touch unrelated notices.
            val postedRooms = AndroidNotifier.activeNotificationRooms().toSet()
            val currentStates = mutableMapOf<ScopedRawRoomId, NotificationReadState>()
            rooms.forEach { room ->
                val key = ScopedRawRoomId(room.sessionId.value, room.summary.roomId.value)
                if (key !in postedRooms) return@forEach
                val current = NotificationReadState(room.summary.info)
                currentStates[key] = current
                val previous = previousStates[key]
                if (current.becameReadSince(previous)) {
                    log.d { "Dismissing notification after synced read state changed for $key" }
                    AndroidNotifier.dismiss(key.sessionId, key.roomId)
                } else if (previous != current) {
                    // Counts can remain nonzero when a newer message arrives. Match the
                    // notification's latest exact event against public/private receipts
                    // and the fully-read marker so a partial read cannot clear new mail.
                    val readEvents = mutableListOf<EventId>()
                    current.fullyReadEventId?.let { readEvents += EventId(it) }
                    UiState.currentClientFor(room.sessionId)?.getRoom(room.summary.roomId)?.use { joinedRoom ->
                        listOf(ReceiptType.READ, ReceiptType.READ_PRIVATE).forEach { type ->
                            joinedRoom.getOwnReadReceipt(type)
                                .onSuccess { event -> event?.let(readEvents::add) }
                                .onFailure { log.w("Failed to inspect synced $type for $key", it) }
                        }
                    }
                    if (readEvents.isNotEmpty()) {
                        AndroidNotifier.maybeAutoDismiss(key.sessionId, key.roomId, readEvents.distinct().map(EventId::value))
                    }
                }
            }
            previousStates = currentStates
        }.launchIn(scope)
    }
}
