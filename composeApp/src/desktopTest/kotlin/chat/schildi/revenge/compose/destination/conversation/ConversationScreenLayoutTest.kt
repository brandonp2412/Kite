package chat.schildi.revenge.compose.destination.conversation

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ConversationScreenLayoutTest {
    @Test
    fun senderDetailsAreHiddenForOneToOneSizedRooms() {
        assertFalse(shouldShowTimelineSenderDetails(null))
        assertFalse(shouldShowTimelineSenderDetails(1))
        assertFalse(shouldShowTimelineSenderDetails(2))
    }

    @Test
    fun senderDetailsAreShownForGroupSizedRooms() {
        assertTrue(shouldShowTimelineSenderDetails(3))
        assertTrue(shouldShowTimelineSenderDetails(24))
    }
}
