package chat.schildi.revenge.notification

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class NotificationConversationTest {
    @Test
    fun bridgedOneToOneRoomWithoutDirectFlagShowsOneName() {
        assertFalse(isGroupNotification(false, false, "Tyla Lockwood · Facebook", "Tyla Lockwood · Facebook", "@tyla:bridge", emptyList()))
        assertFalse(isGroupNotification(false, false, " Tyla Lockwood · Facebook ", "tyla lockwood · facebook", "@tyla:bridge", listOf("@tyla:bridge")))
    }

    @Test
    fun multipleSendersStillRenderAsGroup() {
        assertTrue(isGroupNotification(false, false, "Tyla Lockwood · Facebook", "Tyla Lockwood · Facebook", "@tyla:bridge", listOf("@other:bridge")))
        assertTrue(isGroupNotification(false, false, "Team Chat", "Tyla Lockwood", "@tyla:bridge", emptyList()))
        assertTrue(isGroupNotification(false, false, null, "Tyla Lockwood", "@tyla:bridge", emptyList()))
    }

    @Test
    fun explicitDirectRoomsRemainOneToOne() {
        assertFalse(isGroupNotification(true, false, "Team Chat", "Someone", "@sender:server", emptyList()))
        assertFalse(isGroupNotification(false, true, "Team Chat", "Someone", "@sender:server", emptyList()))
    }
}
