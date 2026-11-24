package chat.schildi.revenge.notification

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class NotificationReadOrderTest {
    @Test
    fun receiptAfterNotificationDismissesOlderMessage() {
        assertTrue(readReceiptCoversNotification("$"+"b", listOf("$"+"c"), listOf("$"+"a", "$"+"b", "$"+"c")))
    }

    @Test
    fun exactReceiptDismissesNotification() {
        assertTrue(readReceiptCoversNotification("$"+"b", listOf("$"+"b"), listOf("$"+"a", "$"+"b")))
    }

    @Test
    fun earlierReceiptDoesNotDismissNewerMessage() {
        assertFalse(readReceiptCoversNotification("$"+"c", listOf("$"+"b"), listOf("$"+"a", "$"+"b", "$"+"c")))
    }

    @Test
    fun absentEventsDoNotCauseDismissal() {
        assertFalse(readReceiptCoversNotification("$"+"b", listOf("$"+"missing"), listOf("$"+"a", "$"+"b")))
        assertFalse(readReceiptCoversNotification("$"+"missing", listOf("$"+"b"), listOf("$"+"a", "$"+"b")))
        assertFalse(readReceiptCoversNotification("$"+"b", emptyList(), listOf("$"+"b")))
    }

    @Test
    fun anyConfirmedReadPositionCanCoverPostedEvent() {
        assertTrue(readReceiptCoversNotification("$"+"b", listOf("$"+"a", "$"+"d"), listOf("$"+"a", "$"+"b", "$"+"c", "$"+"d")))
    }
}
