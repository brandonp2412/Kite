package chat.schildi.revenge.notification

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Verified text from a tapped Android notification, shown until the live Matrix timeline catches up. */
data class NotificationOpenPreview(
    val sessionId: String,
    val roomId: String,
    val eventId: String,
    val text: String,
    val capturedAt: Long = System.currentTimeMillis(),
)

object NotificationOpenPreviews {
    private val mutable = MutableStateFlow<NotificationOpenPreview?>(null)
    val current = mutable.asStateFlow()

    fun show(preview: NotificationOpenPreview) {
        mutable.value = preview
    }

    fun clearIfCurrent(preview: NotificationOpenPreview) {
        mutable.compareAndSet(preview, null)
    }

    fun clearRoom(sessionId: String, roomId: String) {
        mutable.value?.takeIf { it.sessionId == sessionId && it.roomId == roomId }
            ?.let(::clearIfCurrent)
    }
}
