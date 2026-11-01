package chat.schildi.revenge.notification

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class NotificationReadStateTest {
    private fun state(
        unreadMessages: Long = 0,
        unreadNotifications: Long = 0,
        unreadCount: Long = 0,
        manuallyUnread: Boolean = false,
        incompleteUnreadCount: Boolean = false,
        marker: String? = null,
    ) = NotificationReadState(
        unreadMessages,
        unreadNotifications,
        unreadCount,
        manuallyUnread,
        incompleteUnreadCount,
        marker,
    )

    @Test
    fun aSyncedReadTransitionDismissesRoomNotification() {
        assertTrue(state().becameReadSince(state(unreadMessages = 2, unreadNotifications = 1)))
        assertTrue(state().becameReadSince(state(unreadCount = 1)))
        assertTrue(state().becameReadSince(state(manuallyUnread = true)))
    }

    @Test
    fun initialOrStillUnreadStateNeverDismisses() {
        assertFalse(state().becameReadSince(null))
        assertFalse(state().becameReadSince(state()))
        assertFalse(state(unreadMessages = 1).becameReadSince(state(unreadMessages = 2)))
        assertFalse(state(unreadNotifications = 1).becameReadSince(state(unreadNotifications = 2)))
    }

    @Test
    fun incompleteCountsAndNewerUnreadMessagesArePreserved() {
        assertFalse(state(incompleteUnreadCount = true).becameReadSince(state(unreadMessages = 1)))
        assertFalse(state(unreadCount = 1).becameReadSince(state(unreadMessages = 1)))
        assertFalse(state(manuallyUnread = true).becameReadSince(state(unreadMessages = 1)))
    }

    @Test
    fun markerChangeAloneDoesNotClearNewUnreadMessages() {
        assertFalse(state(unreadMessages = 1, marker = "new").becameReadSince(state(unreadMessages = 1, marker = "old")))
        assertFalse(state(marker = "new").becameReadSince(state(marker = "old")))
    }
}
