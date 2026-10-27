package chat.schildi.revenge.notification

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class NotificationOpenPreviewTest {
    @Test
    fun keepsOnlyTheCurrentNotificationAndClearsItForTheOpenedRoom() {
        val older = NotificationOpenPreview("session", "room", "old", "first")
        val latest = older.copy(eventId = "new", text = "second")
        NotificationOpenPreviews.show(older)
        NotificationOpenPreviews.show(latest)
        NotificationOpenPreviews.clearIfCurrent(older)
        assertEquals(latest, NotificationOpenPreviews.current.value)
        NotificationOpenPreviews.clearRoom("session", "other-room")
        assertEquals(latest, NotificationOpenPreviews.current.value)
        NotificationOpenPreviews.clearRoom("session", "room")
        assertNull(NotificationOpenPreviews.current.value)
    }
}
